#!/usr/bin/env ruby
# frozen_string_literal: true

require 'csv'
require 'minitest/autorun'

require_relative '../lib/rra'

# TODO : add RRA::Ledger below
[RRA::HLedger].each do |pta_klass|
  describe pta_klass do
    subject { pta_klass }

    describe '.balance' do
      # TODO: Add a pricer test on balance

      it 'must parse a simple balance query' do
        balance = subject.balance 'Transfers', from_s: <<~JOURNAL
          2023-01-01 Transaction 1
            Transfers:PersonalCredit_PersonalChecking    $ 1234.00
            Personal:Assets:AcmeBank:Checking

          2023-01-02 Transaction 2
            Transfers:PersonalSavings_PersonalChecking   $ 5678.90
            Personal:Assets:AcmeBank:Checking
        JOURNAL

        value(balance.accounts.map(&:fullname)).must_equal ['Transfers:PersonalCredit_PersonalChecking',
                                                            'Transfers:PersonalSavings_PersonalChecking']
        value(balance.accounts[0].amounts.map(&:to_s)).must_equal ['$ 1234.00']
        value(balance.accounts[1].amounts.map(&:to_s)).must_equal ['$ 5678.90']
        value(balance.summary_amounts.map(&:to_s)).must_equal ['$ 6912.90']
      end

      it 'must parse a negative balances query' do
        balance = subject.balance 'Unknown', from_s: <<~JOURNAL
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

        value(balance.accounts.length).must_equal 2
        value(balance.accounts[0].fullname).must_equal 'Personal:Expenses:Unknown'
        value(balance.accounts[0].amounts.length).must_equal 1
        value(balance.accounts[0].amounts[0].to_s).must_equal '$ 750.00'

        value(balance.accounts[1].fullname).must_equal 'Personal:Income:Unknown'
        value(balance.accounts[1].amounts.length).must_equal 1
        value(balance.accounts[1].amounts[0].to_s).must_equal '$ -540.00'

        # Summary line.
        value(balance.summary_amounts.length).must_equal 1
        value(balance.summary_amounts[0].to_s).must_equal '$ 210.00'
      end

      it 'must parse balances in multiple currencies' do
        balance = subject.balance 'Unknown', from_s: <<~JOURNAL
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
    end

    describe '.balance' do
      it 'matches the output of the csv command, on longer queries' do
        # This is just your basic activity, on a mostly unused savings account
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

        register = subject.register 'Personal:Assets:AcmeBank:Savings', related: true, from_s: journal

        csv_rows = CSV.parse(subject.command('register',
                                             'Personal:Assets:AcmeBank:Savings',
                                             from_s: journal,
                                             related: true,
                                             'output-format': 'csv'),
                             headers: true)

        assert_equal csv_rows.length, register.transactions.length

        csv_rows.each_with_index do |csv_row, i|
          value(register.transactions[i].postings.length).must_equal 1
          value(register.transactions[i].postings[0].amounts.length).must_equal 1
          value(register.transactions[i].postings[0].totals.length).must_equal 1
          value(register.transactions[i].date.to_s).must_equal csv_row['date']
          value(register.transactions[i].payee).must_equal csv_row['description']
          value(register.transactions[i].postings[0].account).must_equal csv_row['account']
          value(register.transactions[i].postings[0].amounts[0].to_s).must_equal csv_row['amount']
          value(register.transactions[i].postings[0].totals[0].to_s).must_equal csv_row['total']
        end
      end

      it 'parses multiple commodities and tags' do
        register = subject.register 'Personal:Expenses', from_s: <<~JOURNAL
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

        value(register.transactions.length).must_equal 4

        # Dates:
        value(register.transactions.map(&:date).map(&:to_s)).must_equal %w[2023-02-14 2023-02-16 2023-02-19 2023-02-20]

        # Payees
        value(register.transactions.map(&:payee).map(&:to_s)).must_equal(
          ['Food Lion', '2x Lotto tickets', 'Agua con Gas', 'Carulla']
        )

        # Transaction 1:
        value(register.transactions[0].postings.map(&:account)).must_equal ['Personal:Expenses:Food:Groceries',
                                                                            'Personal:Expenses:Vices:Alcohol']
        value(register.transactions[0].postings.map(&:amounts).flatten.map(&:to_s)).must_equal ['$ 26.18', '$ 18.26']
        value(register.transactions[0].postings.map(&:totals).flatten.map(&:to_s)).must_equal ['$ 26.18', '$ 44.44']
        value(register.transactions[0].postings.map(&:tags)).must_equal(
          [{ 'intention' => 'Personal' },
           { 'Dating' => true, 'ValentinesDay' => true, 'intention' => 'Personal' }]
        )

        # Transaction 2:
        value(register.transactions[1].postings.map(&:account)).must_equal ['Personal:Expenses:Vices:Gambling']
        value(register.transactions[1].postings.map(&:amounts).flatten.map(&:to_s)).must_equal ['$ 2.00']
        value(register.transactions[1].postings.map(&:totals).flatten.map(&:to_s)).must_equal ['$ 46.44']
        value(register.transactions[1].postings.map(&:tags)).must_equal [{ 'intention' => 'Personal', 'Loss' => true }]

        # Transaction 3:
        value(register.transactions[2].postings.map(&:account)).must_equal ['Personal:Expenses:Food:Water']
        value(register.transactions[2].postings.map(&:amounts).flatten.map(&:to_s)).must_equal ['4000.00 COP']
        value(register.transactions[2].postings.map(&:totals).flatten.map(&:to_s)).must_equal ['$ 46.44', '4000.00 COP']
        value(register.transactions[2].postings.map(&:tags)).must_equal [{ 'intention' => 'Personal' }]

        # Transaction 4:
        value(register.transactions[3].postings.map(&:account)).must_equal ['Personal:Expenses:Food:Groceries',
                                                                            'Personal:Expenses:Food:Water']
        value(register.transactions[3].postings.map(&:amounts).flatten.map(&:to_s)).must_equal ['56123.00 COP',
                                                                                                '4000.00 COP']
        value(register.transactions[3].postings.map(&:totals).flatten.map(&:to_s)).must_equal ['$ 46.44',
                                                                                               '60123.00 COP',
                                                                                               '$ 46.44',
                                                                                               '64123.00 COP']
        value(register.transactions[3].postings.map(&:tags)).must_equal [{ 'intention' => 'Personal' }] * 2
      end

      it 'supports price conversion, through :pricer' do
        register = subject.register(
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

        value(register.transactions.map(&:date).map(&:to_s)).must_equal %w[2023-05-01 2023-06-01]
        value(register.transactions.map(&:payee).compact).must_equal []
        value(register.transactions.map(&:postings).flatten.map(&:account)).must_equal ['Personal:Assets:Cash'] * 2
        value(register.transactions.map(&:postings).flatten.map(&:tags)).must_equal [{}] * 2

        # Month 1:
        value(register.transactions[0].postings[0].amounts.map(&:to_s)).must_equal ['$ -684.88', '-1419.75 HNL']
        value(register.transactions[0].postings[0].totals.map(&:to_s)).must_equal ['$ -684.88', '-1419.75 HNL']

        value(register.transactions[0].postings[0].amount_in('$').to_s).must_equal '$ -742.385554'
        value(register.transactions[0].postings[0].total_in('$').to_s).must_equal '$ -742.385554'

        # Month 2:
        value(register.transactions[1].postings[0].amounts.map(&:to_s)).must_equal ['$ -651.09', '-57999.80 CLP']
        value(register.transactions[1].postings[0].totals.map(&:to_s)).must_equal ['$ -1335.97',
                                                                                   '-57999.80 CLP',
                                                                                   '-1419.75 HNL']

        value(register.transactions[1].postings[0].amount_in('$').to_s).must_equal '$ -720.68976'
        value(register.transactions[1].postings[0].total_in('$').to_s).must_equal '$ -1463.075314'
      end
    end
  end
end
