# frozen_string_literal: true

# This class writes the monthly income and expense numbers, by intention, by month
class MonthlyIncomeAndExpensesGrid < RRA::GridBase
  grid 'income_and_expenses_by_intention',
       'Generate Income & Expense Grids',
       'Income & Expense by month (%s)',
       output_path_template: '%s-monthly-income-and-expenses'

  def intentions
    @intentions ||= tag_values 'intention'
  end

  def sheet_header
    ['Date'] + intentions.collect do |intent|
      %w[Income Expense].collect { |direction| [direction, intent].join ' ' }
    end.flatten
  end

  def sheet_body
    table = intentions.each_with_object({}) do |intent, ret|
      %w[Income Expense].each do |direction|
        ret[direction] ||= {}
        ret[direction][intent] = monthly_amounts(format('%%intention=%s', intent.to_s), 'and', direction)
      end
      ret
    end

    # This deserializes our lookup hash(es) into rows:
    months_through_dates(starting_at, ending_at).collect do |month|
      [month.strftime('%m-%y')] + intentions.collect do |intent|
        %w[Income Expense].collect do |direction|
          cell = table[direction][intent][month]
          cell ? cell.abs : nil
        end
      end.flatten
    end
  end
end
