#!/usr/bin/env ruby

require "csv"
require "minitest/autorun"

require 'rra'
require_relative '../lib/rra/fake_journal'

class TestCashBalanceValidation < Minitest::Test
  def test_basic_cash
    journal = FakeJournal.new.basic_cash Date.new(2020, 1, 1), 
      Date.new(2020, 1, 10), '$ 100.00'.to_commodity, 10

    assert_equal(<<~EOD.chomp, journal.to_s)
		2020-01-01 Simple Payee
		  Expense    $ 10.00
		  Cash

		2020-01-02 Simple Payee
		  Expense    $ 10.00
		  Cash

		2020-01-03 Simple Payee
		  Expense    $ 10.00
		  Cash

		2020-01-04 Simple Payee
		  Expense    $ 10.00
		  Cash

		2020-01-05 Simple Payee
		  Expense    $ 10.00
		  Cash

		2020-01-06 Simple Payee
		  Expense    $ 10.00
		  Cash

		2020-01-07 Simple Payee
		  Expense    $ 10.00
		  Cash

		2020-01-08 Simple Payee
		  Expense    $ 10.00
		  Cash

		2020-01-09 Simple Payee
		  Expense    $ 10.00
		  Cash

		2020-01-10 Simple Payee
		  Expense    $ 10.00
		  Cash
    EOD

    balance = RRA::Ledger.balance 'Cash', from_s: journal.to_s
    assert_equal 1, balance.accounts.length
    assert_equal "Cash", balance.accounts[0].fullname
    assert_equal 1, balance.accounts[0].amounts.length
    assert_equal "$ -100.00", balance.accounts[0].amounts[0].to_s

  end

  def test_basic_cash_balance
    # journal = FakeJournal.new.basic_cash Date.new(2020, 1, 1), 
    #   Date.new(2020, 1, 10), '$ 100.00'.to_commodity, 10

		# TODO: Test out some modulus' with the total amout (off by 1/n)
    # puts "Returned:" + ledger_balance(journal).inspect
  end

  def test_basic_cash_dates
		# TODO: The end date is broken... test it out a few ways to figure out where
    # journal = FakeJournal.new.basic_cash Date.new(2020, 1, 1), 
  end

end
