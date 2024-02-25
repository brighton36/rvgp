# frozen_string_literal: true

module RRA
  # This module contains helper methods used throughout RRA. These are just common
  # codepaths, that have little in common, save for their general utility.
  module Utilities
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
