#!/usr/bin/env ruby
# frozen_string_literal: true

require 'csv'
require 'minitest/autorun'

require_relative '../lib/rvgp'

[RVGP::Pta::Ledger, RVGP::Pta::HLedger].each do |pta_klass|
  describe pta_klass do
    subject { pta_klass.new }

    describe "#{pta_klass}#adapter_name" do
      it 'should return the appropriate symbol' do
        value(subject.adapter_name).must_equal subject.is_a?(RVGP::Pta::HLedger) ? :hledger : :ledger
      end
    end

    describe "#{pta_klass} - #oldest_transaction, #newest_transaction_date, and #{pta_klass}#newest_transaction" do
      let(:journal) do
        <<~JOURNAL
          1990-01-01 Wendy's
            Personal:Expenses:Food:Restaurant    $8.44
            Personal:Assets:Cash

          1982-01-01 McDonald's
            Personal:Expenses:Food:Restaurant    $10.15
            Personal:Assets:Cash

          2002-01-01 Burger King
            Personal:Expenses:Food:Restaurant    $3.94
            Personal:Assets:Cash

          2000-01-01 Arby's
            Personal:Expenses:Food:Restaurant    $12.87
            Personal:Assets:Cash
        JOURNAL
      end

      let(:oldest_tx) { subject.oldest_transaction from_s: journal }
      let(:newest_tx) { subject.newest_transaction from_s: journal }

      it 'returns the oldest transaction in the file' do
        value(oldest_tx.payee).must_equal "McDonald's"
        value(oldest_tx.date).must_equal Date.new(1982, 1, 1)
        value(oldest_tx.postings.length).must_equal 2
        value(oldest_tx.postings[0].account).must_equal 'Personal:Expenses:Food:Restaurant'
        value(oldest_tx.postings[0].amounts.map(&:to_s)).must_equal ['$ 10.15']
        value(oldest_tx.postings[1].account).must_equal 'Personal:Assets:Cash'
        value(oldest_tx.postings[1].amounts.map(&:to_s)).must_equal ['$ -10.15']
      end

      it 'returns the newest transaction in the file' do
        value(newest_tx.payee).must_equal 'Burger King'
        value(newest_tx.date).must_equal Date.new(2002, 1, 1)
        value(newest_tx.postings.length).must_equal 2
        value(newest_tx.postings[0].account).must_equal 'Personal:Expenses:Food:Restaurant'
        value(newest_tx.postings[0].amounts.map(&:to_s)).must_equal ['$ 3.94']
        value(newest_tx.postings[1].account).must_equal 'Personal:Assets:Cash'
        value(newest_tx.postings[1].amounts.map(&:to_s)).must_equal ['$ -3.94']
      end

      it 'returns the newest transaction date in the file' do
        # This is a specific optimization, that enables us to use hledger stats in the rvgp/config.rb
        value(subject.newest_transaction_date(from_s: journal)).must_equal Date.new(2002, 1, 1)
      end
    end

    describe "#{pta_klass}#files" do
      it 'returns all the files referenced in a journal' do
        journals = 5.times.map { Tempfile.open %w[rvgp_test .journal] }

        journals[1...].each do |journal|
          journal.write(<<~JOURNAL)
            1990-01-01 Wendy's
              Personal:Expenses:Food:Restaurant    $8.44
              Personal:Assets:Cash
          JOURNAL
          journal.close
        end

        journals[0].write(journals[1...].map do |journal|
          format 'include %s', journal.path
        end.zip(["\n"] * journals.length).flatten.join)

        journals[0].close

        value(subject.files(file: journals[0].path).sort).must_equal journals.map(&:path).sort

      ensure
        journals.each(&:unlink)
      end
    end

    describe "#{pta_klass}#balance" do
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

        # Maybe I should just remove this feature entirely?....
        value(balance.summary_amounts.map(&:to_s)).must_equal ['$ 6912.90'] if subject.hledger?
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
        if subject.hledger?
          value(balance.summary_amounts.length).must_equal 1
          value(balance.summary_amounts[0].to_s).must_equal '$ 210.00'
        end
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
        assert_equal ['$ 41.00', '1847.00 GTQ'], balance.accounts[0].amounts.map(&:to_s).sort

        # Summary line
        if subject.hledger?
          assert_equal 2, balance.summary_amounts.length
          assert_equal '$ 41.00', balance.summary_amounts[0].to_s
          assert_equal '1847.00 GTQ', balance.summary_amounts[1].to_s
        end
      end

      it 'converts commodities, given a pricer' do
        # TODO: Put the TestLedger#test_balance_multiple_with_empty here. Refactored
        skip 'TODO: Put the TestLedger#test_balance_multiple_with_empty here. Refactored'
      end

      it "parses depth #{pta_klass}" do
        balance = pta_klass.new.balance 'Personal:Assets:AcmeBank:Checking',
                                        depth: 1,
                                        from_s: <<~JOURNAL
                                          1996-02-03 Publix
                                            Personal:Expenses:Food:Groceries    $ 123.45
                                            Personal:Assets:AcmeBank:Checking
                                        JOURNAL

        value(balance.accounts.length).must_equal 1
        value(balance.accounts[0].fullname).must_equal 'Personal'
        value(balance.accounts[0].amounts.length).must_equal 1
        value(balance.accounts[0].amounts[0].to_s).must_equal '$ -123.45'
      end
    end

    describe "#{pta_klass}#register" do
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

        # We just use hledger here, rather than maintain two versions of our csv_rows truth table:
        csv_rows = CSV.parse(RVGP::Pta::HLedger.new.command('register',
                                                           'Personal:Assets:AcmeBank:Savings',
                                                           from_s: journal, related: true, 'output-format': 'csv'),
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
           if subject.hledger?
             { 'Dating' => true, 'ValentinesDay' => true, 'intention' => 'Personal' }
           else
             { 'intention' => 'Personal' }
           end]
        )

        # Transaction 2:
        value(register.transactions[1].postings.map(&:account)).must_equal ['Personal:Expenses:Vices:Gambling']
        value(register.transactions[1].postings.map(&:amounts).flatten.map(&:to_s)).must_equal ['$ 2.00']
        value(register.transactions[1].postings.map(&:totals).flatten.map(&:to_s)).must_equal ['$ 46.44']
        value(register.transactions[1].postings.map(&:tags)).must_equal [if subject.hledger?
                                                                           { 'intention' => 'Personal', 'Loss' => true }
                                                                         else
                                                                           { 'intention' => 'Personal' }
                                                                         end]

        # Transaction 3:
        value(register.transactions[2].postings.map(&:account)).must_equal ['Personal:Expenses:Food:Water']
        value(register.transactions[2].postings.map(&:amounts).flatten.map(&:to_s)).must_equal ['4000.00 COP']
        value(register.transactions[2].postings.map(&:totals).flatten.map(&:to_s).sort).must_equal ['$ 46.44',
                                                                                                    '4000.00 COP']
        value(register.transactions[2].postings.map(&:tags)).must_equal [{ 'intention' => 'Personal' }]

        # Transaction 4:
        value(register.transactions[3].postings.map(&:account)).must_equal ['Personal:Expenses:Food:Groceries',
                                                                            'Personal:Expenses:Food:Water']
        value(register.transactions[3].postings.map(&:amounts).flatten.map(&:to_s)).must_equal ['56123.00 COP',
                                                                                                '4000.00 COP']
        value(register.transactions[3].postings.map(&:totals).flatten.map(&:to_s).sort).must_equal ['$ 46.44',
                                                                                                    '$ 46.44',
                                                                                                    '60123.00 COP',
                                                                                                    '64123.00 COP']
        value(register.transactions[3].postings.map(&:tags)).must_equal [{ 'intention' => 'Personal' }] * 2
      end

      it 'supports price conversion, through :pricer' do
        transactions = subject.register(
          'Personal:Assets:Cash',
          monthly: true,
          pricer: RVGP::Journal::Pricer.new(<<~PRICES),
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
        ).transactions

        value(transactions.map(&:date).map(&:to_s)).must_equal %w[2023-05-01 2023-06-01]
        value(transactions.map(&:payee).compact).must_equal(subject.hledger? ? [] : ['- 23-May-31', '- 23-Jun-30'])
        value(transactions.map(&:postings).flatten.map(&:account)).must_equal ['Personal:Assets:Cash'] * 2
        value(transactions.map(&:postings).flatten.map(&:tags)).must_equal [{}] * 2

        # Month 1:
        value(transactions[0].postings[0].amounts.map(&:to_s).sort).must_equal ['$ -684.88', '-1419.75 HNL']
        value(transactions[0].postings[0].totals.map(&:to_s).sort).must_equal ['$ -684.88', '-1419.75 HNL']

        value(transactions[0].postings[0].amount_in('$').to_s).must_equal '$ -742.385554'
        value(transactions[0].postings[0].total_in('$').to_s).must_equal '$ -742.385554'

        # Month 2:

        # NOTE: This is a bug in ledger. Seemingly, the register command shows the .80. The correct amount.
        # However, the xml output, shows '.8'. I don't think there are any great solutions to this, so, for
        # now, I'm doing this in the tests:
        expected_clp = subject.hledger? ? '-57999.80 CLP' : '-57999.8 CLP'

        value(transactions[1].postings[0].amounts.map(&:to_s)).must_equal ['$ -651.09', expected_clp]
        value(transactions[1].postings[0].totals.map(&:to_s).sort).must_equal ['$ -1335.97',
                                                                               '-1419.75 HNL',
                                                                               expected_clp]

        value(transactions[1].postings[0].amount_in('$').to_s).must_equal '$ -720.68976'
        value(transactions[1].postings[0].total_in('$').to_s).must_equal '$ -1463.075314'
      end
    end

    describe "#{pta_klass}#tags" do
      let(:journal) do
        <<~JOURNAL
          2023-01-01 Transaction 1
            Personal:Expenses:TaggedExpense    $ 1.00
            ; color: red
            ; vacation: Hawaii
            Personal:Assets:AcmeBank:Checking

          2023-01-02 Transaction 2
            Personal:Expenses:TaggedExpense    $ 2.00
            ; color: orange
            ; :business:
            Personal:Assets:AcmeBank:Checking

          2023-01-03 Transaction 3
            Personal:Expenses:TaggedExpense    $ 3.00
            ; color: yellow
            ; :medical:
            Personal:Assets:AcmeBank:Checking

          2023-01-04 Transaction 4
            Personal:Expenses:TaggedExpense    $ 4.00
            ; color: green
            Personal:Assets:AcmeBank:Checking

          2023-01-05 Transaction 5
            Personal:Expenses:TaggedExpense    $ 5.00
            ; color: blue
            Personal:Assets:AcmeBank:Checking

          2023-01-06 Transaction 6
            Personal:Expenses:TaggedExpense    $ 6.00
            ; color: indigo
            Personal:Assets:AcmeBank:Checking

          2023-01-07 Transaction 7
            Personal:Expenses:TaggedExpense    $ 7.00
            ; color: violet
            Personal:Assets:AcmeBank:Checking

          2023-01-08 Transaction 8
            Personal:Expenses:TaggedExpense    $ 8.00
            ; vacation: Argentina
            Personal:Assets:AcmeBank:Checking

          2023-01-09 Transaction 9
            Personal:Expenses:TaggedExpense    $ 9.00
            ; vacation: Germany
            Personal:Assets:AcmeBank:Checking

          2023-01-10 Transaction 10
            Personal:Expenses:TaggedExpense    $ 10.00
            ; vacation: Japan
            Personal:Assets:AcmeBank:Checking
        JOURNAL
      end

      it 'parses tags' do
        value(subject.tags(from_s: journal)).must_equal %w[business color medical vacation]
        value(subject.tags('color', from_s: journal, values: true)).must_equal(
          %w[blue green indigo orange red violet yellow]
        )
        value(subject.tags('vacation', from_s: journal, values: true)).must_equal %w[Argentina Germany Hawaii Japan]

        value(subject.tags(values: true, from_s: journal)).must_equal(
          # See the note on #tags to understand the ethos here, and why we can't/won't conform the output between pta
          # adapter implementations on this query
          if subject.ledger?
            ['business', 'color: blue', 'color: green', 'color: indigo', 'color: orange', 'color: red', 'color: violet',
             'color: yellow', 'medical', 'vacation: Argentina', 'vacation: Germany', 'vacation: Hawaii',
             'vacation: Japan']
          else
            %w[Argentina Germany Hawaii Japan blue green indigo orange red violet yellow]
          end
        )
      end
    end
  end
end

describe 'pta adapter errata' do
  # This is a bug in ledger. The register output works fine. The xml output, does not. Possibly... we should
  # warn here, so that when the problem is solved, we can ... know it?
  # alternatively, we can just fix this in our code, I think. By adjusting the ledger adapter, for the case
  # when 0 is returned....
  describe '--empty bug' do
    let(:args) do
      # NOTE: This errata only triggers, if there's another tx in the listings, for that month. Hence the Reading
      ['Personal:Expenses',
       { monthly: true, begin: Date.new(2023, 7, 1), end: Date.new(2023, 8, 1), from_s: <<~JOURNAL }]
         2023/07/11 Shakespeare and Company
             Personal:Expenses:Hobbies:Reading        $ 12.34
             Personal:Assets:AcmeBank:Checking

         2023/07/13 GAP Clothing
             Personal:Expenses:Clothes                $ 50.01
             Personal:Assets:AcmeBank:Checking

         2023/07/24 GAP Clothing (RMA)
             Personal:Expenses:Clothes               $ -50.01
             Personal:Assets:AcmeBank:Checking
       JOURNAL
    end

    let(:args_with_fix) do
      [args[0], args[1].merge(empty: false)]
    end

    it 'returns nil for the case of a query whose net change is 0' do
      # This was a very specific bug that crept up, mostly because ledger handles this a bit differently than
      # hledger. If two transactions 'cancel each other out' in a given month, hledger reports nil, and ledger
      # reports '0'. This may be a case where all 0's, without a currency code, should return nil. And, I just
      # happened to find that case exhibited in this circumstance.
      #
      # This test also ensures that if there's only one such transaction - we receive an empty transactions list.

      # Hledger just works, and these tests are here for posterity. Asserting that hledger works as expected
      [args, args_with_fix].each do |a|
        transactions = RVGP::Pta::HLedger.new.register(*a).transactions
        value(transactions.length).must_equal 1
        value(transactions[0].payee).must_be_nil
        value(transactions[0].postings.length).must_equal 1
        value(transactions[0].postings[0].amounts.map(&:to_s)).must_equal ['$ 12.34']
      end

      # These specs just define the error, through our expectations of how it manefests:
      transactions = RVGP::Pta::Ledger.new.register(*args).transactions
      value(transactions.length).must_equal 1
      value(transactions[0].payee).must_equal '- 23-Jul-31'
      value(transactions[0].postings.length).must_equal 2
      value(transactions[0].postings[0].amounts.map(&:to_s)).must_equal ['$ 0.00']
      value(transactions[0].postings[1].amounts.map(&:to_s)).must_equal ['$ 12.34']

      # This is the fix:
      transactions = RVGP::Pta::Ledger.new.register(*args_with_fix).transactions
      value(transactions.length).must_equal 1
      value(transactions[0].payee).must_equal '- 23-Jul-31'
      value(transactions[0].postings.length).must_equal 1
      value(transactions[0].postings[0].amounts.map(&:to_s)).must_equal ['$ 12.34']
    end
  end
end
