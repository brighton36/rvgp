# frozen_string_literal: true

module RVGP
  # This module contains helper methods used throughout RVGP. These are just common
  # codepaths, that have little in common, save for their general utility.
  module Utilities
    class CsvObject
      include RVGP::Utilities
      # TODO Let's see where this object goes before we document it... I'm not sure what we want this to be
      # yet.

      def initialize(row, &)
        if row.is_a? Array
          @row = row
        else
          row.each_pair { |attr, val| instance_variable_set "@#{snake_case(attr)}", val unless attr.nil? }
        end
        instance_eval(&) if block_given?
      end

      def [](num)
        @row[num]
      end

      def method_missing(sym, *_args, &)
        instance_variable_defined?("@#{sym}") ? instance_variable_get("@#{sym}") : super
      end

      def respond_to_missing?(sym, include_priv)
        instance_variable_defined?("@#{sym}") || super
      end

      class << self
        include RVGP::Utilities

        def from_file(path, encoding: nil, **)
          from_string(File.read(path, encoding:), **)
        end

        def from_string(str, decorator: nil, skip_lines: nil, trim_lines: nil, reverse: false, sort_by: nil, **)
          CSV.parse(skip_and_trim(str, skip_lines:, trim_lines:), **)
             .map { |row| new(row, &decorator) }
             .tap do |rows|
               rows.sort_by!(&sort_by) if sort_by
               rows.reverse! if reverse
             end
        end

        private

        def skip_and_trim(str, skip_lines: nil, trim_lines: nil)
          start_offset = 0
          end_offset = str.length

          if trim_lines
            trim_lines_regex = string_to_regex trim_lines.to_s
            trim_lines_regex ||= /(?:[^\n]*\n?){0,#{trim_lines}}\Z/m
            match = trim_lines_regex.match str
            end_offset = match.begin 0 if match
            return String.new if end_offset.zero?
          end

          if skip_lines
            skip_lines_regex = string_to_regex skip_lines.to_s
            skip_lines_regex ||= /(?:[^\n]*\n){0,#{skip_lines}}/m
            match = skip_lines_regex.match str
            start_offset = match.end 0 if match
          end

          # If our cursors overlapped, that means we're just returning an empty string
          return '' if end_offset < start_offset

          str[start_offset..(end_offset - 1)]
        end
      end
    end

    # This returns each month in a series from the first date, to the last, in the
    # provided array of dates
    # @overload months_through(date, ...)
    #   @param [Array<Date>] date A date, that will be used to calculate the range of months to construct a range from.
    #   @param [Array<Date>] ... More dates. This method will automatically select the max and min from the sample
    #                            provided.
    # @return [Array<Date>] An array, containing a Date, set to the first of every month, in the provided range.
    def months_through(*args)
      dates = args.flatten.uniq.sort

      ret = []
      unless dates.empty?
        d = Date.new dates.first.year, dates.first.month, 1 # start_at
        while d <= Date.new(dates.last.year, dates.last.month, 1) # end_at
          ret << d
          d >>= 1
        end
      end
      ret
    end

    # Convert the provided string, into a Regexp. Note that the the ixm suffixes are supported, unlike
    # ruby's Regexp.new(str) method
    # @param [String] str A string, in the 'standard' regexp format: '/Running (?:to|at) the Park/i'
    # @return [Regexp] The conversion to a useable regexp, for the provided string
    def string_to_regex(str)
      if %r{\A/(.*)/([imx]?[imx]?[imx]?)\Z}.match str
        Regexp.new(::Regexp.last_match(1), ::Regexp.last_match(2).chars.map do |c|
          case c
          when 'i' then Regexp::IGNORECASE
          when 'x' then Regexp::EXTENDED
          when 'm' then Regexp::MULTILINE
          end
        end.reduce(:|))
      end
    end

    def snake_case(str, map_using = :downcase, join_with = '_')
      str.scan(/(?:[A-Z]?[a-z]+|[A-Z]+)/).map(&map_using.to_proc).join(join_with)
    end

    def camel_case(str)
      snake_case(str, :capitalize, nil)
    end
  end
end
