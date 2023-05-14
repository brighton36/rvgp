# frozen_string_literal: true

# This class writes the cashflow numbers, by intention, by month
class CashFlowGrid < RRA::GridBase
  include HasMultipleSheets

  grid 'cashflow', 'Generate Cashflow Grids', 'Cashflows by month (%s)'

  has_sheets('cashflow') do |year|
    tag_values('intention', year: year).reject { |intention| intention == :Ignored }
  end

  def sheet_header(_)
    ['Account'] + collect_months { |month| month.strftime('%m-%y') }
  end

  def sheet_body(sheet)
    # NOTE: I think it only makes sense to sort these by account name. Mostly
    #       because any other sorting mechanism wouldn't 'line up' with the
    #       other years. But, it's also nice that the git diff's would be
    #       easier to parse.
    monthly_amounts_by_account(format('%%intention=%s', sheet.to_s))
      .sort_by { |acct, _| acct }
      .collect { |account, by_month| [account] + collect_months { |m| by_month[m].round(2) if by_month[m] } }
  end

  private

  def collect_months(&block)
    months_through_dates(starting_at, ending_at).collect(&block)
  end
end
