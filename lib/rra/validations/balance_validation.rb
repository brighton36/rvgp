class BalanceValidation < RRA::JournalValidationBase
  def validate
    if transformer.balances.nil? || transformer.balances.length == 0
      warning! "No balance checkpoints found."
    else
      is_account_valid = true
      cite_balances = transformer.balances.collect{|d, expected_balance_s| 
        expected_balance = expected_balance_s.to_commodity

        balances_on_day = RRA::Ledger.balance transformer.from, depth: 1, end: d.to_s
        
        found = balances_on_day.accounts.collect(&:amounts).flatten.find{|amount|
          amount.code == expected_balance.code }

        if found
          found_as_s = "Found: %s" % found.to_s
        else
          found_as_s = '(Nil)'
          found = RRA::Journal::Commodity.from_symbol_and_amount expected_balance.code, 0
        end

        is_valid = expected_balance == found
        is_account_valid = false unless is_valid
        
        "(%s) Expected: %s %s" % [ d.to_s, expected_balance.to_s,
          RRA.pastel.send( (is_valid) ? :green : :red, found_as_s ) ]
      }

      error! "Failed Checkpoint(s):", cite_balances unless is_account_valid
    end
  end
end

