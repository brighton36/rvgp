# frozen_string_literal: true

# This validation asserts that the ledger-reported balance, matches a provided
# balance, on a given day. Presumably, this provisional balance, comes from a
# bank statement.
class BalanceValidation < RRA::JournalValidationBase
  def validate
    if transformer.balances.nil? || transformer.balances.empty?
      warning! 'No balance checkpoints found.'
    else
      is_account_valid = true
      cite_balances = transformer.balances.map do |d, expected_balance_s|
        expected_balance = expected_balance_s.to_commodity

        balances_on_day = RRA::HLedger.balance transformer.from, depth: 1, end: d.to_s

        balances_found = balances_on_day.accounts.map(&:amounts).flatten.find_all do |amount|
          amount.code == expected_balance.code
        end

        found = if balances_found.empty?
                  # Rather than operate from nil, we'll establish that we're '0' of units
                  # of the expected symbol
                  RRA::Journal::Commodity.from_symbol_and_amount expected_balance.code, 0
                else
                  balances_found.sum
                end

        found_as_s = if found
                       format('Found: %s', found.to_s)
                     else
                       found = RRA::Journal::Commodity.from_symbol_and_amount expected_balance.code, 0
                       '(Nil)'
                     end

        is_valid = expected_balance == found
        is_account_valid = false unless is_valid

        format('(%<day>s) Expected: %<expected>s %<indicator>s',
               day: d.to_s,
               expected: expected_balance.to_s,
               indicator: RRA.pastel.send(is_valid ? :green : :red, found_as_s))
      end

      error! 'Failed Checkpoint(s):', cite_balances unless is_account_valid
    end
  end
end
