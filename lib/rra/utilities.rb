module RRA::Utilities
  # This returns each month in a series from the first date, to the last, in the
  # provided array of dates
  def months_through_dates(*args)
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

  def string_to_regex(s)
    if %r{\A/(.*)/([imx]?[imx]?[imx]?)\Z}.match s
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
