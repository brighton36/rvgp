module RRA::Utilities
  # This returns each month in a series from the first date, to the last, in the
  # provided array of dates
  def months_through_dates(*args)
    dates = args.flatten.uniq.sort 

    ret = []
    if dates.length > 0
      d = Date.new dates.first.year, dates.first.month, 1 # start_at
      while d <= Date.new(dates.last.year, dates.last.month, 1) # end_at
        ret << d
        d = d >> 1
      end
    end
    ret
  end

  def tag_values(for_tag, options = {})
    # NOTE: Don't call this function after a rake clean, because you'll end up
    #       without any tags. 
    # NOTE: Though tempting, probably don't cache this value.
    # NOTE: Let's try not to pass options direct to command(), it's possible we 
    #       want to switch between ledger/hledger, and this will achieve that.
    args = ['tags', '--values', for_tag]
    args += ['--begin', options[:year], '--end', options[:year]+1] if options[:year]
    args += [options[:query]].flatten if options[:query]
    RRA::HLedger.command(*args).lines.collect{|l| l.chomp.to_sym}.sort
  end

  def string_to_regex(s)
    Regexp.new $1, $2.chars.collect{|c| 
      case c
        when 'i' then Regexp::IGNORECASE
        when 'x' then Regexp::EXTENDED
        when 'm' then Regexp::MULTILINE
      end
    }.reduce(:|) if /\A\/(.*)\/([imx]?[imx]?[imx]?)\Z/.match s
  end
end
