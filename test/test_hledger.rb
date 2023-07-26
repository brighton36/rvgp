#!/usr/bin/env ruby
# frozen_string_literal: true

require 'csv'
require 'minitest/autorun'

require_relative '../lib/rra'

class TestHLedger < Minitest::Test
  def test_balance_multiple
    balance = RRA::HLedger.balance 'Unknown', from_s: <<~JOURNAL
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
    JOURNAL

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
    balance = RRA::HLedger.balance 'Unknown', from_s: <<~JOURNAL
      2023-01-01 Transaction 1
        Personal:Expenses:Unknown    $ 41.00
        Personal:Assets:AcmeBank:Checking

      2023-01-02 Transaction 2
        Personal:Expenses:Unknown    1847.00 GTQ
        Personal:Assets:AcmeBank:Checking
    JOURNAL

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

  # TODO: Add a pricer test on balance

  def test_balance_transfers
    balance = RRA::HLedger.balance 'Transfers', from_s: <<~JOURNAL
      2023-01-01 Transaction 1
        Transfers:PersonalCredit_PersonalChecking    $ 1234.00
        Personal:Assets:AcmeBank:Checking

      2023-01-02 Transaction 2
        Transfers:PersonalSavings_PersonalChecking   $ 5678.90
        Personal:Assets:AcmeBank:Checking
    JOURNAL

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

  # This is just your basic activity, on a mostly unused savings account
  def test_basic_acmebank_savings
    journal = <<~JOURNAL
      2021/01/26 INTEREST PAYMENT
        Personal:Income:AcmeBank:Interest      $ -7.89
        Personal:Assets:AcmeBank:Savings

      2021/01/26 MONTHLY SERVICE FEE
        Personal:Expenses:Banking:Fees:AcmeBank     $ 5.00
        Personal:Assets:AcmeBank:Savings

      2021/02/23 INTEREST PAYMENT
        Personal:Income:AcmeBank:Interest      $ -7.89
        Personal:Assets:AcmeBank:Savings

      2021/02/23 MONTHLY SERVICE FEE
        Personal:Expenses:Banking:Fees:AcmeBank     $ 5.00
        Personal:Assets:AcmeBank:Savings

      2021/03/15 ONLINE TRANSFER FROM PERSONAL CHECKING ON 03/13/21
        Transfers:PersonalSavings_PersonalChecking   $ -100.00
        Personal:Assets:AcmeBank:Savings

      2021/03/22 INTEREST PAYMENT
        Personal:Income:AcmeBank:Interest      $ -7.90
        Personal:Assets:AcmeBank:Savings

      2021/03/22 MONTHLY SERVICE FEE
        Personal:Expenses:Banking:Fees:AcmeBank     $ 5.00
        Personal:Assets:AcmeBank:Savings

      2021/04/22 INTEREST PAYMENT
        Personal:Income:AcmeBank:Interest      $ -7.89
        Personal:Assets:AcmeBank:Savings

      2021/04/22 MONTHLY SERVICE FEE
        Personal:Expenses:Banking:Fees:AcmeBank     $ 5.00
        Personal:Assets:AcmeBank:Savings

      2021/05/24 INTEREST PAYMENT
        Personal:Income:AcmeBank:Interest      $ -7.89
        Personal:Assets:AcmeBank:Savings

      2021/05/24 MONTHLY SERVICE FEE
        Personal:Expenses:Banking:Fees:AcmeBank     $ 5.00
        Personal:Assets:AcmeBank:Savings

      2021/06/22 INTEREST PAYMENT
        Personal:Income:AcmeBank:Interest      $ -7.89
        Personal:Assets:AcmeBank:Savings

      2021/06/22 MONTHLY SERVICE FEE
        Personal:Expenses:Banking:Fees:AcmeBank     $ 5.00
        Personal:Assets:AcmeBank:Savings

      2021/07/23 INTEREST PAYMENT
        Personal:Income:AcmeBank:Interest      $ -7.90
        Personal:Assets:AcmeBank:Savings

      2021/07/23 MONTHLY SERVICE FEE
        Personal:Expenses:Banking:Fees:AcmeBank     $ 5.00
        Personal:Assets:AcmeBank:Savings
    JOURNAL

    register = RRA::HLedger.register 'Personal:Assets:AcmeBank:Savings', related: true, from_s: journal

    csv_rows = CSV.parse(RRA::HLedger.command('register',
                                              'Personal:Assets:AcmeBank:Savings',
                                              from_s: journal,
                                              related: true,
                                              'output-format': 'csv'),
                         headers: true)

    assert_equal csv_rows.length, register.transactions.length

    # All:
    csv_rows.each_with_index do |csv_row, i|
      assert_equal 1, register.transactions[i].postings.length
      assert_equal 1, register.transactions[i].postings[0].amounts.length
      assert_equal 1, register.transactions[i].postings[0].totals.length
      assert_equal csv_row['date'], register.transactions[i].date.to_s
      assert_equal csv_row['description'], register.transactions[i].payee
      assert_equal csv_row['account'], register.transactions[i].postings[0].account
      assert_equal csv_row['amount'].to_commodity.to_s, register.transactions[i].postings[0].amounts[0].to_s
      assert_equal csv_row['total'].to_commodity.to_s, register.transactions[i].postings[0].totals[0].to_s
    end
  end

  def test_personal_cash_multiple_commodities_and_tags
    register = RRA::HLedger.register 'Personal:Expenses', from_s: <<~JOURNAL
      2023-02-14 Food Lion
        Personal:Expenses:Food:Groceries    $26.18 ; intention: Personal
        Personal:Expenses:Vices:Alcohol    $18.26
        ; Dating:
        ; ValentinesDay:
        ; intention: Personal
        Personal:Assets:Cash

      2023-02-16 2x Lotto tickets
        Personal:Expenses:Vices:Gambling    $ 2.00
        ; Loss:
        ; intention: Personal
        Personal:Assets:Cash

      2023-02-19 Agua con Gas
        Personal:Expenses:Food:Water    4000.00 COP
        ; intention: Personal
        Personal:Assets:Cash

      2023-02-20 Carulla
        Personal:Expenses:Food:Groceries    56123.00 COP
        ; intention: Personal
        Personal:Expenses:Food:Water         4000.00 COP
        ; intention: Personal
        Personal:Assets:Cash
    JOURNAL

    assert_equal 4, register.transactions.length

    # Transaction 1:
    assert_equal '2023-02-14', register.transactions[0].date.to_s
    assert_equal 'Food Lion', register.transactions[0].payee
    assert_equal 2, register.transactions[0].postings.length

    assert_equal 'Personal:Expenses:Food:Groceries', register.transactions[0].postings[0].account
    assert_equal 1, register.transactions[0].postings[0].amounts.length
    assert_equal 1, register.transactions[0].postings[0].totals.length
    assert_equal '$ 26.18', register.transactions[0].postings[0].amounts[0].to_s
    assert_equal '$ 26.18', register.transactions[0].postings[0].totals[0].to_s
    assert_equal({ 'intention' => 'Personal' }, register.transactions[0].postings[0].tags)

    assert_equal 'Personal:Expenses:Vices:Alcohol', register.transactions[0].postings[1].account
    assert_equal 1, register.transactions[0].postings[1].amounts.length
    assert_equal 1, register.transactions[0].postings[1].totals.length
    assert_equal '$ 18.26', register.transactions[0].postings[1].amounts[0].to_s
    assert_equal '$ 44.44', register.transactions[0].postings[1].totals[0].to_s
    assert_equal({ 'Dating' => true, 'ValentinesDay' => true, 'intention' => 'Personal' }, register.transactions[0].postings[1].tags)

    # Transaction 2:
    assert_equal '2023-02-16', register.transactions[1].date.to_s
    assert_equal '2x Lotto tickets', register.transactions[1].payee
    assert_equal 1, register.transactions[1].postings.length

    assert_equal 'Personal:Expenses:Vices:Gambling', register.transactions[1].postings[0].account
    assert_equal 1, register.transactions[1].postings[0].amounts.length
    assert_equal 1, register.transactions[1].postings[0].totals.length
    assert_equal '$ 2.00', register.transactions[1].postings[0].amounts[0].to_s
    assert_equal '$ 46.44', register.transactions[1].postings[0].totals[0].to_s
    assert_equal({ 'intention' => 'Personal', 'Loss' => true }, register.transactions[1].postings[0].tags)

    # Transaction 3:
    assert_equal '2023-02-19', register.transactions[2].date.to_s
    assert_equal 'Agua con Gas', register.transactions[2].payee
    assert_equal 1, register.transactions[2].postings.length

    assert_equal 'Personal:Expenses:Food:Water', register.transactions[2].postings[0].account
    assert_equal 1, register.transactions[2].postings[0].amounts.length
    assert_equal 2, register.transactions[2].postings[0].totals.length
    assert_equal '4000.00 COP', register.transactions[2].postings[0].amounts[0].to_s
    assert_equal '$ 46.44', register.transactions[2].postings[0].totals[0].to_s
    assert_equal '4000.00 COP', register.transactions[2].postings[0].totals[1].to_s
    assert_equal({ 'intention' => 'Personal' }, register.transactions[2].postings[0].tags)

    # Transaction 4:
    assert_equal '2023-02-20', register.transactions[3].date.to_s
    assert_equal 'Carulla', register.transactions[3].payee
    assert_equal 2, register.transactions[3].postings.length

    assert_equal 'Personal:Expenses:Food:Groceries', register.transactions[3].postings[0].account
    assert_equal 1, register.transactions[3].postings[0].amounts.length
    assert_equal 2, register.transactions[3].postings[0].totals.length
    assert_equal '56123.00 COP', register.transactions[3].postings[0].amounts[0].to_s
    assert_equal '$ 46.44', register.transactions[3].postings[0].totals[0].to_s
    assert_equal '60123.00 COP', register.transactions[3].postings[0].totals[1].to_s
    assert_equal({ 'intention' => 'Personal' }, register.transactions[3].postings[0].tags)

    assert_equal 'Personal:Expenses:Food:Water', register.transactions[3].postings[1].account
    assert_equal 1, register.transactions[3].postings[1].amounts.length
    assert_equal 2, register.transactions[3].postings[1].totals.length
    assert_equal '4000.00 COP', register.transactions[3].postings[1].amounts[0].to_s
    assert_equal '$ 46.44', register.transactions[3].postings[1].totals[0].to_s
    assert_equal '64123.00 COP', register.transactions[3].postings[1].totals[1].to_s
    assert_equal({ 'intention' => 'Personal' }, register.transactions[3].postings[1].tags)
  end

  def test_multiple_commodity_postings
    register = RRA::HLedger.register(
      'Personal:Assets:Cash',
      monthly: true,
      pricer: RRA::Pricer.new(<<~PRICES),
        P 2023-05-01 HNL $0.040504
        P 2023-06-01 CLP $0.0012
      PRICES
      from_s: <<~JOURNAL
        2023-05-02 Flight to Honduras
          Personal:Expenses:Transportation:Airline   $ 252.78
          Personal:Assets:Cash

        2023-05-14 Roatan Dive Center
          Personal:Expenses:Hobbies:SCUBA   876.54 HNL
          Personal:Assets:Cash

        2023-05-15 Eldon's Supermarket
          Personal:Expenses:Food:Groceries   543.21 HNL
          Personal:Assets:Cash

        2023-05-30 Flight to Chile
          Personal:Expenses:Transportation:Airline   $ 432.10
          Personal:Assets:Cash

        2023-06-02 Nevados de Chillan
          Personal:Expenses:Hobbies:Snowboarding   33143.60 CLP
          Personal:Assets:Cash

        2023-06-03 La Cabrera Chile Isidora
          Personal:Expenses:Food:Restaurants    24856.20 CLP
          Personal:Assets:Cash

        2023-06-14 Flight Home
          Personal:Expenses:Transportation:Airline   $ 651.09
          Personal:Assets:Cash
      JOURNAL
    )

    assert_equal 2, register.transactions.length

    # Month 1:
    assert_equal '2023-05-01', register.transactions[0].date.to_s
    assert_nil register.transactions[0].payee
    assert_equal 1, register.transactions[0].postings.length
    assert_equal 'Personal:Assets:Cash', register.transactions[0].postings[0].account
    assert_equal({}, register.transactions[0].postings[0].tags)
    assert_equal ['$ -684.88', '-1419.75 HNL'], register.transactions[0].postings[0].amounts.map(&:to_s)
    assert_equal ['$ -684.88', '-1419.75 HNL'], register.transactions[0].postings[0].totals.map(&:to_s)
    assert_equal '$ -742.385554', register.transactions[0].postings[0].amount_in('$').to_s
    assert_equal '$ -742.385554', register.transactions[0].postings[0].total_in('$').to_s

    # Month 2:
    assert_equal '2023-06-01', register.transactions[1].date.to_s
    assert_nil register.transactions[1].payee
    assert_equal({}, register.transactions[1].postings[0].tags)
    assert_equal 1, register.transactions[1].postings.length
    assert_equal 'Personal:Assets:Cash', register.transactions[1].postings[0].account
    assert_equal ['$ -651.09', '-57999.80 CLP'], register.transactions[1].postings[0].amounts.map(&:to_s)
    assert_equal ['$ -1335.97', '-57999.80 CLP', '-1419.75 HNL'], register.transactions[1].postings[0].totals.map(&:to_s)
    assert_equal '$ -720.68976', register.transactions[1].postings[0].amount_in('$').to_s
    assert_equal '$ -1463.075314', register.transactions[1].postings[0].total_in('$').to_s
  end
end
