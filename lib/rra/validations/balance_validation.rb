# frozen_string_literal: true

module RRA
  module Validations
    # This validation asserts that the ledger-reported balance, matches a provided
    # balance, on a given day. These balances, should be stipulated in a section
    # of your transformer, that looks like this:
    # ```
    #    balances:
    #    '2022-01-01': $ 105.63
    #    '2022-09-01': $ 300.29
    #    '2022-10-01': $ 400.33
    # ```
    # These balances are expected to come from a bank statement, and this validation
    # ensures that rra is matching the records of your financial institution
    class BalanceValidation < RRA::Base::JournalValidation
      # If there are no checkpoints in the 'balances' line of the transformer, this
      # fires a warning. If there are checkpoints, then, we scan the register to
      # ensure that the balance of the transformer.from, on the checkpoint date,
      # matches the ledger/hledger balance, on that date. (and if it doesnt,
      # fires an error)
      def validate
        if transformer.balances.nil? || transformer.balances.empty?
          warning! 'No balance checkpoints found.'
        else
          is_account_valid = true
          cite_balances = transformer.balances.map do |d, expected_balance_s|
            expected_balance = expected_balance_s.to_commodity

            balances_on_day = pta.balance transformer.from,
                                          depth: 1,
                                          end: d.to_s,
                                          file: RRA.app.config.project_journal_path

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
  end
end
