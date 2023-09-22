# frozen_string_literal: true

# This class writes the cashflow numbers, by month
class CashFlowGrid < RRA::Base::Grid
  grid 'cashflow', 'Generate Cashflow Grids', 'Cashflows by month (%s)',
       output_path_template: '%s-cashflow'

  def sheet_header
    ['Account'] + collect_months { |month| month.strftime('%m-%y') }
  end

  def sheet_body
    # NOTE: I think it only makes sense to sort these by account name. Mostly
    #       because any other sorting mechanism wouldn't 'line up' with the
    #       other years. But, it's also nice that the git diff's would be
    #       easier to parse.
    monthly_amounts_by_account
      .sort_by { |acct, _| acct }
      .collect { |account, by_month| [account] + collect_months { |m| by_month[m].round(2) if by_month[m] } }
  end

  private

  def collect_months(&block)
    months_through_dates(starting_at, ending_at).collect(&block)
  end
end
