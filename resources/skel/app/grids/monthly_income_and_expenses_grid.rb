# frozen_string_literal: true

# This class writes the monthly income and expense numbers, by month
class MonthlyIncomeAndExpensesGrid < RVGP::Base::Grid
  builds '%<year>s-monthly-income-and-expenses', grids: parameters_per_year

  def header
    %w[Date Income Expense]
  end

  def body
    table = { 'Income' => monthly_amounts('Income'), 'Expense' => monthly_amounts('Expense') }

    # This deserializes our lookup hash(es) into rows:
    months_through(starting_at, ending_at).collect do |month|
      [month.strftime('%m-%y')] + %w[Income Expense].map do |direction|
        cell = table[direction][month]
        cell ? cell.abs : nil
      end
    end
  end
end
