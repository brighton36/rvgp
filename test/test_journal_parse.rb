#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'

require_relative '../lib/rvgp'

# Tests for RRA::Journal
class TestJournalParse < Minitest::Test
  SAMPLE_TAG_FORMATS_JOURNAL = <<~JOURNAL
    2021-01-20 Lawn Mowing
      Personal:Expenses:Home:LawnMaintenance    $ 100.00
      ; intention: HomeMaintenance
      ; property: 123GreenSt
      Personal:Assets:Bankname:Checking

    2021-01-20 Fancy Restaurant
    ;:SmallBusiness:
      Personal:Expenses:Dining    $ 50.00
      ; wine: red
      ; :Pasta:Italian:Vegetarian:
      Personal:Assets:Bankname:Checking

    ; These next four were pulled from: https://hledger.org/tags-tutorial.html

    2016/09/25 ACME Costume ; Halloween:
      Expenses:Entertainment     $45.99
      Liabilities:CreditCard

    2020/05/20 AcmeWrappings.com
      Expenses:Clothing  $58.99  ; fabric:wool, width:20, color:ancient white
      Liabilities:MonsterCard

    2016/10/31 Grocery Store
      Expenses     $3.52   ;  on sale today item:candy
      Liabilities:CreditCard

    2016/10/31 Grocery Store
      Expenses     $3.52   ;  item:candy, on sale today
      Liabilities:CreditCard
  JOURNAL

  SAMPLE_CURRENCY_DECLARATION_JOURNAL = <<~JOURNAL
    2021-06-16 1100 HNL
      Personal:Assets:Cash                                  1100 HNL @@ $ 45.83
      ; intention: Ignored
      Personal:Expenses:Banking:Fees:IrlExchangeSlippage    $ 4.17
      ; intention: Personal
      Personal:Assets:Cash

    ; These are from: https://www.ledger-cli.org/3.0/doc/ledger3.html
    2012-04-10 My Broker
      Assets:Brokerage            10 AAPL {$50.00}
      Assets:Brokerage:Cash      $-500.00

    2012-04-10 My Broker
      Assets:Brokerage:Cash       $750.00
      Assets:Brokerage            -10 AAPL {{$500.00}} @@ $750.00
      Income:Capital Gains       $-250.00

    2012-04-10 My Broker
      Assets:Brokerage:Cash       $375.00
      Assets:Brokerage            -5 AAPL {$50.00} [2012-04-10] @@ $375.00
      Income:Capital Gains       $-125.00

    2012-04-10 My Broker
      Assets:Brokerage:Cash       $375.00
      Assets:Brokerage            -5 AAPL {$50.00} [2012-04-10] (Oh my!) @@ $375.00
      Income:Capital Gains       $-125.00

    2012-04-10 My Broker
      Assets:Brokerage:Cash       $375.00
      Assets:Brokerage            -5 AAPL {$50.00} ((ten_dollars)) @@ $375.00
      Income:Capital Gains       $-125.00

    2012-04-10 My Broker
      A:B:Cash       $375.00
      A:B     -5 AAPL {$50.00} ((s, d, t -> market(0, date, t))) @@ $375.00
      Income:Capital Gains       $-125.00

    2010/05/31 Farmer's Market
      Assets:My Larder           100 apples        @ $0.200000
      Assets:My Larder           100 pineapples    @ $0.33
      Assets:My Larder           100 "crab apples" @ $0.04
      Assets:Checking

    2012-04-10 My Broker
      Assets:Brokerage            10 AAPL @ =$50.00
      Assets:Brokerage:Cash      $-500.00

    2012-04-10 My Broker
      Assets:Brokerage            10 AAPL {=$50.00}
      Assets:Brokerage:Cash      $-500.00

    2012-03-10 My Broker
      Assets:Brokerage             (5 AAPL * 2) @ ($500.00 / 10)
      Assets:Brokerage:Cash
  JOURNAL

  def test_journal_tag_parsing
    journal = RRA::Journal.parse SAMPLE_TAG_FORMATS_JOURNAL

    assert_equal 6, journal.postings.length

    # Posting 0
    posting0 = journal.postings[0]
    assert_equal Date.new(2021, 1, 20), posting0.date
    assert_equal 'Lawn Mowing', posting0.description
    assert_equal 0, posting0.tags.length
    assert_equal 2, posting0.transfers.length

    # Posting 0, Transfer 0
    assert_equal 'Personal:Expenses:Home:LawnMaintenance', posting0.transfers[0].account
    assert_equal '$ 100.00', posting0.transfers[0].commodity.to_s
    assert_equal 2, posting0.transfers[0].tags.length
    assert_equal ['intention: HomeMaintenance', 'property: 123GreenSt'], posting0.transfers[0].tags.collect(&:to_s)

    # Posting 0, Transfer 1
    assert_equal 'Personal:Assets:Bankname:Checking', posting0.transfers[1].account
    assert_nil posting0.transfers[1].commodity

    # Posting 1
    posting1 = journal.postings[1]

    assert_equal Date.new(2021, 1, 20), posting1.date
    assert_equal 'Fancy Restaurant', posting1.description
    assert_equal ['SmallBusiness'], posting1.tags.collect(&:to_s)
    assert_equal 2, posting1.transfers.length

    # Posting 1, Transfer 0
    assert_equal 'Personal:Expenses:Dining', posting1.transfers[0].account
    assert_equal '$ 50.00', posting1.transfers[0].commodity.to_s
    assert_equal ['wine: red', 'Pasta', 'Italian', 'Vegetarian'], posting1.transfers[0].tags.collect(&:to_s)

    # Posting 1, Transfer 1
    assert_equal 'Personal:Assets:Bankname:Checking', posting1.transfers[1].account
    assert_nil posting1.transfers[1].commodity

    # Posting 2
    posting2 = journal.postings[2]

    assert_equal Date.new(2016, 9, 25), posting2.date
    assert_equal 'ACME Costume', posting2.description
    assert_equal ['Halloween'], posting2.tags.collect(&:to_s)
    assert_equal 2, posting2.transfers.length

    # Posting 2, Transfer 0
    assert_equal 'Expenses:Entertainment', posting2.transfers[0].account
    assert_equal '$ 45.99', posting2.transfers[0].commodity.to_s
    assert_equal 0, posting2.transfers[0].tags.length

    # Posting 2, Transfer 1
    assert_equal 'Liabilities:CreditCard', posting2.transfers[1].account
    assert_nil posting2.transfers[1].commodity

    # Posting 3
    posting3 = journal.postings[3]

    assert_equal Date.new(2020, 5, 20), posting3.date
    assert_equal 'AcmeWrappings.com', posting3.description
    assert_equal 0, posting3.tags.length
    assert_equal 2, posting3.transfers.length

    # Posting 3, Transfer 0
    assert_equal 'Expenses:Clothing', posting3.transfers[0].account
    assert_equal '$ 58.99', posting3.transfers[0].commodity.to_s
    assert_equal ['fabric: wool', 'width: 20', 'color: ancient white'], posting3.transfers[0].tags.collect(&:to_s)

    # Posting 3, Transfer 1
    assert_equal 'Liabilities:MonsterCard', posting3.transfers[1].account
    assert_nil posting3.transfers[1].commodity

    # Posting 4
    posting4 = journal.postings[4]

    assert_equal Date.new(2016, 10, 31), posting4.date
    assert_equal 'Grocery Store', posting4.description
    assert_equal 0, posting4.tags.length
    assert_equal 2, posting4.transfers.length

    # Posting 4, Transfer 0
    assert_equal 'Expenses', posting4.transfers[0].account
    assert_equal '$ 3.52', posting4.transfers[0].commodity.to_s
    assert_equal ['item: candy'], posting4.transfers[0].tags.collect(&:to_s)

    # Posting 4, Transfer 1
    assert_equal 'Liabilities:CreditCard', posting4.transfers[1].account
    assert_nil posting4.transfers[1].commodity

    # Posting 5
    posting5 = journal.postings[5]

    assert_equal Date.new(2016, 10, 31), posting5.date
    assert_equal 'Grocery Store', posting5.description
    assert_equal 0, posting5.tags.length
    assert_equal 2, posting5.transfers.length

    # Posting 5, Transfer 0
    assert_equal 'Expenses', posting5.transfers[0].account
    assert_equal '$ 3.52', posting5.transfers[0].commodity.to_s
    assert_equal ['item: candy'], posting5.transfers[0].tags.collect(&:to_s)

    # Posting 5, Transfer 1
    assert_equal 'Liabilities:CreditCard', posting5.transfers[1].account
    assert_nil posting5.transfers[1].commodity
  end

  def test_currency_purchase_parsing
    journal = RRA::Journal.parse SAMPLE_CURRENCY_DECLARATION_JOURNAL

    assert_equal 11, journal.postings.length

    # Posting 0
    posting0 = journal.postings[0]
    assert_equal Date.new(2021, 6, 16), posting0.date
    assert_equal '1100 HNL', posting0.description
    assert_equal 0, posting0.tags.length
    assert_equal 3, posting0.transfers.length

    # Posting 0, Transfer 0
    assert_equal 'Personal:Assets:Cash', posting0.transfers[0].account
    assert_nil posting0.transfers[0].commodity
    assert_equal '1100.00 HNL', posting0.transfers[0].complex_commodity.left.to_s
    assert_equal :per_lot, posting0.transfers[0].complex_commodity.operation
    assert_equal '$ 45.83', posting0.transfers[0].complex_commodity.right.to_s
    assert_equal ['intention: Ignored'], posting0.transfers[0].tags.collect(&:to_s)

    # Posting 0, Transfer 1
    assert_equal 'Personal:Expenses:Banking:Fees:IrlExchangeSlippage', posting0.transfers[1].account
    assert_equal '$ 4.17', posting0.transfers[1].commodity.to_s

    # Posting 0, Transfer 2
    assert_equal 'Personal:Assets:Cash', posting0.transfers[2].account
    assert_nil posting0.transfers[2].commodity
    assert_nil posting0.transfers[2].complex_commodity

    assert_equal true, posting0.valid?

    assert_equal [
      '2021-06-16 1100 HNL',
      '  Personal:Assets:Cash                                  1100.00 HNL @@ $ 45.83',
      '  ; intention: Ignored',
      '  Personal:Expenses:Banking:Fees:IrlExchangeSlippage    $ 4.17',
      '  ; intention: Personal',
      '  Personal:Assets:Cash'
    ].join("\n"), posting0.to_ledger

    # Posting 1
    posting1 = journal.postings[1]
    assert_equal Date.new(2012, 4, 10), posting1.date
    assert_equal 'My Broker', posting1.description
    assert_equal 0, posting1.tags.length
    assert_equal 2, posting1.transfers.length

    # Posting 1, Transfer 0
    assert_equal 'Assets:Brokerage', posting1.transfers[0].account
    assert_nil posting1.transfers[0].commodity
    assert_equal '10 AAPL', posting1.transfers[0].complex_commodity.left.to_s
    assert_nil posting1.transfers[0].complex_commodity.operation
    assert_nil posting1.transfers[0].complex_commodity.right
    assert_equal :per_unit, posting1.transfers[0].complex_commodity.left_lot_operation
    assert_equal '$ 50.00', posting1.transfers[0].complex_commodity.left_lot.to_s
    assert_equal 0, posting1.transfers[0].tags.length

    # Posting 1, Transfer 1
    assert_equal 'Assets:Brokerage:Cash', posting1.transfers[1].account
    assert_equal '$ -500.00', posting1.transfers[1].commodity.to_s
    assert_equal [
      '2012-04-10 My Broker',
      '  Assets:Brokerage         10 AAPL {$ 50.00}',
      '  Assets:Brokerage:Cash    $ -500.00'
    ].join("\n"), posting1.to_ledger

    # Posting 2
    posting2 = journal.postings[2]
    assert_equal Date.new(2012, 4, 10), posting2.date
    assert_equal 'My Broker', posting2.description
    assert_equal 0, posting2.tags.length
    assert_equal 3, posting2.transfers.length

    # Posting 2, Transfer 0
    assert_equal 'Assets:Brokerage:Cash', posting2.transfers[0].account
    assert_equal '$ 750.00', posting2.transfers[0].commodity.to_s

    # Posting 2, Transfer 1
    assert_equal 'Assets:Brokerage', posting2.transfers[1].account
    assert_nil posting2.transfers[1].commodity
    assert_equal '-10 AAPL', posting2.transfers[1].complex_commodity.left.to_s
    assert_equal :per_lot, posting2.transfers[1].complex_commodity.left_lot_operation
    assert_equal '$ 500.00', posting2.transfers[1].complex_commodity.left_lot.to_s

    assert_equal :per_lot, posting2.transfers[1].complex_commodity.operation
    assert_equal '$ 750.00', posting2.transfers[1].complex_commodity.right.to_s
    assert_equal 0, posting2.transfers[1].tags.length

    # Posting 2, Transfer 2
    assert_equal 'Income:Capital Gains', posting2.transfers[2].account
    assert_equal '$ -250.00', posting2.transfers[2].commodity.to_s
    assert_equal [
      '2012-04-10 My Broker',
      '  Assets:Brokerage:Cash    $ 750.00',
      '  Assets:Brokerage         -10 AAPL {{$ 500.00}} @@ $ 750.00',
      '  Income:Capital Gains     $ -250.00'
    ].join("\n"), posting2.to_ledger

    # Posting 3
    posting3 = journal.postings[3]
    assert_equal Date.new(2012, 4, 10), posting3.date
    assert_equal 'My Broker', posting3.description
    assert_equal 0, posting3.tags.length
    assert_equal 3, posting3.transfers.length

    # Posting 3, Transfer 0
    assert_equal 'Assets:Brokerage:Cash', posting3.transfers[0].account
    assert_equal '$ 375.00', posting3.transfers[0].commodity.to_s

    # Posting 3, Transfer 1
    assert_equal 'Assets:Brokerage', posting3.transfers[1].account
    assert_nil posting3.transfers[1].commodity
    assert_equal '-5 AAPL', posting3.transfers[1].complex_commodity.left.to_s
    assert_equal :per_unit, posting3.transfers[1].complex_commodity.left_lot_operation
    assert_equal '$ 50.00', posting3.transfers[1].complex_commodity.left_lot.to_s
    assert_equal '2012-04-10', posting3.transfers[1].complex_commodity.left_date.to_s
    assert_equal :per_lot, posting3.transfers[1].complex_commodity.operation
    assert_equal '$ 375.00', posting3.transfers[1].complex_commodity.right.to_s
    assert_equal 0, posting3.transfers[1].tags.length

    # Posting 3, Transfer 2
    assert_equal 'Income:Capital Gains', posting3.transfers[2].account
    assert_equal '$ -125.00', posting3.transfers[2].commodity.to_s

    assert_equal [
      '2012-04-10 My Broker',
      '  Assets:Brokerage:Cash    $ 375.00',
      '  Assets:Brokerage         -5 AAPL {$ 50.00} [2012-04-10] @@ $ 375.00',
      '  Income:Capital Gains     $ -125.00'
    ].join("\n"), posting3.to_ledger

    # Posting 4
    posting4 = journal.postings[4]
    assert_equal Date.new(2012, 4, 10), posting4.date
    assert_equal 'My Broker', posting4.description
    assert_equal 0, posting4.tags.length
    assert_equal 3, posting4.transfers.length

    # Posting 4, Transfer 0
    assert_equal 'Assets:Brokerage:Cash', posting4.transfers[0].account
    assert_equal '$ 375.00', posting4.transfers[0].commodity.to_s

    # Posting 4, Transfer 1
    assert_equal 'Assets:Brokerage', posting4.transfers[1].account
    assert_nil posting4.transfers[1].commodity
    assert_equal '-5 AAPL', posting4.transfers[1].complex_commodity.left.to_s
    assert_equal :per_unit, posting4.transfers[1].complex_commodity.left_lot_operation
    assert_equal '$ 50.00', posting4.transfers[1].complex_commodity.left_lot.to_s
    assert_equal '2012-04-10', posting4.transfers[1].complex_commodity.left_date.to_s
    assert_equal 'Oh my!', posting4.transfers[1].complex_commodity.left_expression
    assert_equal :per_lot, posting4.transfers[1].complex_commodity.operation
    assert_equal '$ 375.00', posting4.transfers[1].complex_commodity.right.to_s
    assert_equal 0, posting4.transfers[1].tags.length

    # Posting 4, Transfer 2
    assert_equal 'Income:Capital Gains', posting4.transfers[2].account
    assert_equal '$ -125.00', posting4.transfers[2].commodity.to_s

    assert_equal [
      '2012-04-10 My Broker',
      '  Assets:Brokerage:Cash    $ 375.00',
      '  Assets:Brokerage         -5 AAPL {$ 50.00} [2012-04-10] (Oh my!) @@ $ 375.00',
      '  Income:Capital Gains     $ -125.00'
    ].join("\n"), posting4.to_ledger

    # Posting 5
    posting5 = journal.postings[5]
    assert_equal Date.new(2012, 4, 10), posting5.date
    assert_equal 'My Broker', posting5.description
    assert_equal 0, posting5.tags.length
    assert_equal 3, posting5.transfers.length

    # Posting 5, Transfer 0
    assert_equal 'Assets:Brokerage:Cash', posting5.transfers[0].account
    assert_equal '$ 375.00', posting5.transfers[0].commodity.to_s

    # Posting 5, Transfer 1
    assert_equal 'Assets:Brokerage', posting5.transfers[1].account
    assert_nil posting5.transfers[1].commodity
    assert_equal '-5 AAPL', posting5.transfers[1].complex_commodity.left.to_s
    assert_equal :per_unit, posting5.transfers[1].complex_commodity.left_lot_operation
    assert_equal '$ 50.00', posting5.transfers[1].complex_commodity.left_lot.to_s
    assert_equal 'ten_dollars', posting5.transfers[1].complex_commodity.left_lambda.to_s
    assert_equal :per_lot, posting5.transfers[1].complex_commodity.operation
    assert_equal '$ 375.00', posting5.transfers[1].complex_commodity.right.to_s
    assert_equal 0, posting5.transfers[1].tags.length

    # Posting 5, Transfer 2
    assert_equal 'Income:Capital Gains', posting5.transfers[2].account
    assert_equal '$ -125.00', posting5.transfers[2].commodity.to_s

    assert_equal [
      '2012-04-10 My Broker',
      '  Assets:Brokerage:Cash    $ 375.00',
      '  Assets:Brokerage         -5 AAPL {$ 50.00} ((ten_dollars)) @@ $ 375.00',
      '  Income:Capital Gains     $ -125.00'
    ].join("\n"), posting5.to_ledger

    # Posting 6
    posting6 = journal.postings[6]
    assert_equal Date.new(2012, 4, 10), posting6.date
    assert_equal 'My Broker', posting6.description
    assert_equal 0, posting6.tags.length
    assert_equal 3, posting6.transfers.length

    # Posting 6, Transfer 0
    assert_equal 'A:B:Cash', posting6.transfers[0].account
    assert_equal '$ 375.00', posting6.transfers[0].commodity.to_s

    # Posting 6, Transfer 1
    assert_equal 'A:B', posting6.transfers[1].account
    assert_nil posting6.transfers[1].commodity
    assert_equal '-5 AAPL', posting6.transfers[1].complex_commodity.left.to_s
    assert_equal :per_unit, posting6.transfers[1].complex_commodity.left_lot_operation
    assert_equal '$ 50.00', posting6.transfers[1].complex_commodity.left_lot.to_s

    assert_equal 's, d, t -> market(0, date, t)', posting6.transfers[1].complex_commodity.left_lambda.to_s
    assert_equal :per_lot, posting6.transfers[1].complex_commodity.operation
    assert_equal '$ 375.00', posting6.transfers[1].complex_commodity.right.to_s
    assert_equal 0, posting6.transfers[1].tags.length

    # Posting 6, Transfer 2
    assert_equal 'Income:Capital Gains', posting6.transfers[2].account
    assert_equal '$ -125.00', posting6.transfers[2].commodity.to_s

    assert_equal [
      '2012-04-10 My Broker',
      '  A:B:Cash                $ 375.00',
      '  A:B                     -5 AAPL {$ 50.00} ((s, d, t -> market(0, date, t))) @@ $ 375.00',
      '  Income:Capital Gains    $ -125.00'
    ].join("\n"), posting6.to_ledger

    # Posting 7
    posting7 = journal.postings[7]
    assert_equal Date.new(2010, 5, 31), posting7.date
    assert_equal "Farmer's Market", posting7.description
    assert_equal 0, posting7.tags.length
    assert_equal 4, posting7.transfers.length

    # Posting 7, Transfer 0
    assert_equal 'Assets:My Larder', posting7.transfers[0].account
    assert_equal :per_unit, posting7.transfers[0].complex_commodity.operation
    assert_equal '100 apples', posting7.transfers[0].complex_commodity.left.to_s
    assert_equal '$ 0.200000', posting7.transfers[0].complex_commodity.right.to_s

    # Posting 7, Transfer 1
    assert_equal 'Assets:My Larder', posting7.transfers[1].account
    assert_equal :per_unit, posting7.transfers[1].complex_commodity.operation
    assert_equal '100 pineapples', posting7.transfers[1].complex_commodity.left.to_s
    assert_equal '$ 0.33', posting7.transfers[1].complex_commodity.right.to_s

    # Posting 7, Transfer 2
    assert_equal 'Assets:My Larder', posting7.transfers[2].account
    assert_equal :per_unit, posting7.transfers[2].complex_commodity.operation
    assert_equal '100 "crab apples"', posting7.transfers[2].complex_commodity.left.to_s
    assert_equal '$ 0.04', posting7.transfers[2].complex_commodity.right.to_s

    # Posting 7, Transfer 3
    assert_equal 'Assets:Checking', posting7.transfers[3].account
    assert_nil posting7.transfers[3].commodity

    assert_equal [
      "2010-05-31 Farmer's Market",
      '  Assets:My Larder    100 apples @ $ 0.200000',
      '  Assets:My Larder    100 pineapples @ $ 0.33',
      '  Assets:My Larder    100 "crab apples" @ $ 0.04',
      '  Assets:Checking'
    ].join("\n"), posting7.to_ledger

    # Posting 8
    posting8 = journal.postings[8]
    assert_equal Date.new(2012, 4, 10), posting8.date
    assert_equal 'My Broker', posting8.description
    assert_equal 0, posting8.tags.length
    assert_equal 2, posting8.transfers.length

    # Posting 8, Transfer 0
    assert_equal 'Assets:Brokerage', posting8.transfers[0].account
    assert_equal '10 AAPL', posting8.transfers[0].complex_commodity.left.to_s
    assert_equal :per_unit, posting8.transfers[0].complex_commodity.operation
    assert_equal true, posting8.transfers[0].complex_commodity.right_is_equal
    assert_equal '$ 50.00', posting8.transfers[0].complex_commodity.right.to_s

    # Posting 8, Transfer 1
    assert_equal 'Assets:Brokerage:Cash', posting8.transfers[1].account
    assert_equal '$ -500.00', posting8.transfers[1].commodity.to_s

    assert_equal [
      '2012-04-10 My Broker',
      '  Assets:Brokerage         10 AAPL @ = $ 50.00',
      '  Assets:Brokerage:Cash    $ -500.00'
    ].join("\n"), posting8.to_ledger

    # Posting 9
    posting9 = journal.postings[9]
    assert_equal Date.new(2012, 4, 10), posting9.date
    assert_equal 'My Broker', posting9.description
    assert_equal 0, posting9.tags.length
    assert_equal 2, posting9.transfers.length

    # Posting 9, Transfer 0
    assert_equal 'Assets:Brokerage', posting9.transfers[0].account
    assert_equal '10 AAPL', posting9.transfers[0].complex_commodity.left.to_s
    assert_equal '$ 50.00', posting9.transfers[0].complex_commodity.left_lot.to_s
    assert_equal true, posting9.transfers[0].complex_commodity.left_lot_is_equal

    # Posting 9, Transfer 1
    assert_equal 'Assets:Brokerage:Cash', posting9.transfers[1].account
    assert_equal '$ -500.00', posting9.transfers[1].commodity.to_s

    assert_equal [
      '2012-04-10 My Broker',
      '  Assets:Brokerage         10 AAPL {=$ 50.00}',
      '  Assets:Brokerage:Cash    $ -500.00'
    ].join("\n"), posting9.to_ledger

    # Posting 10
    posting10 = journal.postings[10]
    assert_equal Date.new(2012, 3, 10), posting10.date
    assert_equal 'My Broker', posting10.description
    assert_equal 0, posting10.tags.length
    assert_equal 2, posting10.transfers.length

    # Posting 10, Transfer 0
    assert_equal 'Assets:Brokerage', posting10.transfers[0].account
    assert_equal '5 AAPL * 2', posting10.transfers[0].complex_commodity.left_expression
    assert_equal '$500.00 / 10', posting10.transfers[0].complex_commodity.right_expression
    assert_equal :per_unit, posting10.transfers[0].complex_commodity.operation

    # Posting 10, Transfer 1
    assert_equal 'Assets:Brokerage:Cash', posting10.transfers[1].account
    assert_equal [
      '2012-03-10 My Broker',
      '  Assets:Brokerage    (5 AAPL * 2) @ ($500.00 / 10)',
      '  Assets:Brokerage:Cash'
    ].join("\n"), posting10.to_ledger
  end
end
