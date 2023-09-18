# frozen_string_literal: true

# This class writes the monthly income and expense numbers, by month
class MonthlyIncomeAndExpensesGrid < RRA::GridBase
  grid 'income_and_expenses',
       'Generate Income & Expense Grids',
       'Income & Expense by month (%s)',
       output_path_template: '%s-monthly-income-and-expenses'

  def sheet_header
    %w[Date Income Expense]
  end

  def sheet_body
    table = { 'Income' => monthly_amounts('Income'), 'Expense' => monthly_amounts('Expense') }

    # This deserializes our lookup hash(es) into rows:
    months_through_dates(starting_at, ending_at).collect do |month|
      [month.strftime('%m-%y')] + %w[Income Expense].map do |direction|
        cell = table[direction][month]
        cell ? cell.abs : nil
      end
    end
  end
end
