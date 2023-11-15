# frozen_string_literal: true

# This class writes the cashflow numbers, by month
class CashFlowGrid < RRA::Base::Grid
  grid 'cashflow', 'Generate Cashflow Grids', 'Cashflows by month (%s)',
       output_path_template: '%s-cashflow'

  def sheet_header
    ['Account'] + map_months { |month| month.strftime('%m-%y') }
  end

  def sheet_body
    # NOTE: I think it only makes sense to sort these by account name. Mostly
    #       because any other sorting mechanism wouldn't 'line up' with the
    #       other years. But, it's also nice that the git diff's would be
    #       easier to parse.
    monthly_amounts_by_account
      .sort_by { |acct, _| acct }
      .map { |account, by_month| [account] + map_months { |m| by_month[m].round(2) if by_month[m] } }
  end

  private

  def map_months(&block)
    months_through(starting_at, ending_at).map(&block)
  end
end
