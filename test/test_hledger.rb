#!/usr/bin/env ruby
# frozen_string_literal: true

require 'csv'
require 'minitest/autorun'

require_relative '../lib/rra'

class TestHLedger < Minitest::Test
  def test_balance_multiple
    balance = RRA::HLedger.balance 'Unknown', from_s: <<~PTA
      2023-01-01 Transaction 1
        Personal:Expenses:Unknown    $ 700.00
        Personal:Assets:AcmeBank:Checking

      2023-01-02 Transaction 2
        Personal:Income:Unknown    $ -500.00
        Personal:Assets:AcmeBank:Checking

      2023-01-03 Transaction 3
        Personal:Expenses:Unknown    $ 50.00
        Personal:Assets:AcmeBank:Checking

      2023-01-04 Transaction 4
        Personal:Income:Unknown    $ -40.00
        Personal:Assets:AcmeBank:Checking
    PTA

    assert_equal 2, balance.accounts.length

    assert_equal 'Personal:Expenses:Unknown', balance.accounts[0].fullname
    assert_equal 1, balance.accounts[0].amounts.length
    assert_equal '$ 750.00', balance.accounts[0].amounts[0].to_s

    assert_equal 'Personal:Income:Unknown', balance.accounts[1].fullname
    assert_equal 1, balance.accounts[1].amounts.length
    assert_equal '$ -540.00', balance.accounts[1].amounts[0].to_s

    # Summary line
    assert_equal 1, balance.summary_amounts.length
    assert_equal '$ 210.00', balance.summary_amounts[0].to_s
  end

  def test_balance_currency_multiple
    balance = RRA::HLedger.balance 'Unknown', from_s: <<~PTA
      2023-01-01 Transaction 1
        Personal:Expenses:Unknown    $ 41.00
        Personal:Assets:AcmeBank:Checking

      2023-01-02 Transaction 2
        Personal:Expenses:Unknown    1847.00 GTQ
        Personal:Assets:AcmeBank:Checking
    PTA

    assert_equal 1, balance.accounts.length
    assert_equal 'Personal:Expenses:Unknown', balance.accounts[0].fullname
    assert_equal 2, balance.accounts[0].amounts.length
    assert_equal '$ 41.00', balance.accounts[0].amounts[0].to_s
    assert_equal '1847.00 GTQ', balance.accounts[0].amounts[1].to_s

    # Summary line
    assert_equal 2, balance.summary_amounts.length
    assert_equal '$ 41.00', balance.summary_amounts[0].to_s
    assert_equal '1847.00 GTQ', balance.summary_amounts[1].to_s
  end

  def test_balance_transfers
    balance = RRA::HLedger.balance 'Transfers', from_s: <<~PTA
      2023-01-01 Transaction 1
        Transfers:PersonalCredit_PersonalChecking    $ 1234.00
        Personal:Assets:AcmeBank:Checking

      2023-01-02 Transaction 2
        Transfers:PersonalSavings_PersonalChecking   $ 5678.90
        Personal:Assets:AcmeBank:Checking
    PTA

    assert_equal 2, balance.accounts.length

    assert_equal 'Transfers:PersonalCredit_PersonalChecking', balance.accounts[0].fullname
    assert_equal 1, balance.accounts[0].amounts.length
    assert_equal '$ 1234.00', balance.accounts[0].amounts[0].to_s

    assert_equal 'Transfers:PersonalSavings_PersonalChecking', balance.accounts[1].fullname
    assert_equal 1, balance.accounts[1].amounts.length
    assert_equal '$ 5678.90', balance.accounts[1].amounts[0].to_s

    # Summary line
    assert_equal 1, balance.summary_amounts.length
    assert_equal '$ 6912.90', balance.summary_amounts[0].to_s
  end
end
