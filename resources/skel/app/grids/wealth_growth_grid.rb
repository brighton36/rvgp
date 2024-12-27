# frozen_string_literal: true

# This class writes the wealth growth grid, by month
class WealthGrowthGrid < RVGP::Base::Grid
  builds '%<year>s-wealth-growth', grids: parameters_per_year

  def header
    %w[Date Assets Liabilities]
  end

  def body
    # NOTE: If we're having a problem with prices not matching outputs,
    # depending on whether we're rebuilding the whole grids directory, as
    # compared to just rebuilding the newest year, it's probably because of
    # the notes on prices there at the bottom of prices.db
    assets, liabilities = *%w[Assets Liabilities].collect do |acct|
      monthly_totals acct, accrue_before_begin: true
    end

    months = months_through starting_at, ending_at

    months.collect.with_index do |month, i|
      # NOTE: The reason we use this last_month hack, is because ledger tends to
      # omit column values, if there's no 'activity' in a category, at the end
      # of the display range. hledger doesn't do that, and we can probably nix
      # this if/when we switch the register command over to hledger...
      last_month = months[i - 1] if i.positive?

      [month.strftime('%m-%y'),
       assets[month] || assets[last_month],
       liabilities[month] || liabilities[last_month]]
    end
  end
end
