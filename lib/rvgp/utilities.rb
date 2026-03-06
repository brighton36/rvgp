# frozen_string_literal: true

module RVGP
  # This module contains helper methods used throughout RVGP. These are just common
  # codepaths, that have little in common, save for their general utility.
  module Utilities
    class CsvObject
      HEADER_SPLITTER = /(?:[A-Z]?[a-z]+|[A-Z]+)/

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

      def snake_case(str)
        str.scan(HEADER_SPLITTER).map(&:downcase).join('_')
      end

      class << self
        def from_file(path, **)
          transform_rows [:read, path], **
        end

        def from_string(str, **)
          transform_rows [:parse, str], **
        end

        private

        def transform_rows(csv_send, decorator: nil, reverse: false, **)
          CSV.send(*csv_send, **).map { |row| new(row, &decorator) }.tap { |rows| rows.reverse! if reverse }
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
          d = d >> 1
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
  end
end
