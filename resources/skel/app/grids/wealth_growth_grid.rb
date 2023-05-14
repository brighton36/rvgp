# frozen_string_literal: true

# This class writes the wealth growth grid, by month
class WealthGrowthGrid < RRA::GridBase
  grid 'wealth_growth', 'Generate Wealth Growth Grids', 'Wealth Growth by month (%s)',
       output_path_template: '%s-wealth-growth'

  def sheet_header
    %w[Date Assets Liabilities]
  end

  def sheet_body
    # NOTE: If we're having a problem with prices not matching outputs,
    # depending on whether we're rebuilding the whole grids directory, as
    # compared to just rebuilding the newest year, it's probably because of
    # the notes on prices there at the bottom of prices.db
    assets, liabilities = *%w[Assets Liabilities].collect do |acct|
      monthly_totals acct, accrue_before_begin: true
    end

    months_through_dates(assets.keys, liabilities.keys).collect do |month|
      [month.strftime('%m-%y'), assets[month], liabilities[month]]
    end
  end
end
