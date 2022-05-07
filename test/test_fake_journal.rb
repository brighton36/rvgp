#!/usr/bin/env ruby

require "csv"
require "minitest/autorun"

require_relative '../lib/rra'
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

    balance = RRA::Ledger.balance 'Expense', from_s: journal.to_s
    assert_equal 1, balance.accounts.length
    assert_equal "Expense", balance.accounts[0].fullname
    assert_equal 1, balance.accounts[0].amounts.length
    assert_equal "$ 100.00", balance.accounts[0].amounts[0].to_s
  end

  def test_basic_cash_balance
    10.times.collect{rand(1..10000000)}.each do |i|
      amount = ('$ %.2f' % (i.to_f/100) ).to_commodity

      journal = FakeJournal.new.basic_cash(Date.new(2020, 1, 1), 
        Date.new(2020, 1, 10), amount, 10)

      balance = RRA::Ledger.balance 'Expense', from_s: journal.to_s

      assert_equal 1, balance.accounts.length
      assert_equal "Expense", balance.accounts[0].fullname
      assert_equal 1, balance.accounts[0].amounts.length
      assert_equal amount.to_s, balance.accounts[0].amounts[0].to_s
    end

  end

  def test_basic_cash_dates
    assert_equal ["2020-01-01", "2020-01-03", "2020-01-05", "2020-01-07", 
      "2020-01-09", "2020-01-11", "2020-01-13", "2020-01-15", "2020-01-17", 
      "2020-01-20"], FakeJournal.new.basic_cash(
        Date.new(2020, 1, 1), Date.new(2020, 1, 20), 
        '$ 100.00'.to_commodity, 10
      ).postings.collect(&:date).collect(&:to_s)

    assert_equal ["2020-01-01", "2020-02-09", "2020-03-19", "2020-04-27", 
      "2020-06-05", "2020-07-14", "2020-08-22", "2020-09-30", "2020-11-08", 
      "2020-12-20"], 
      FakeJournal.new.basic_cash(
        Date.new(2020, 1, 1), Date.new(2020, 12, 20), 
        '$ 100.00'.to_commodity, 10
      ).postings.collect(&:date).collect(&:to_s)
  end

end
