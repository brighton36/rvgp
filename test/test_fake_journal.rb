#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'

require_relative '../lib/rra'
require_relative '../lib/rra/fakers/fake_journal'

# Minitest class, used to test RRA::Fakers::FakeJournal
class TestFakeJournal < Minitest::Test
  def test_basic_cash
    journal = RRA::Fakers::FakeJournal.basic_cash from: Date.new(2020, 1, 1), to: Date.new(2020, 1, 10)

    assert_kind_of RRA::Journal, journal
    assert_equal 10, journal.postings.length
    assert_equal %w[2020-01-01 2020-01-02 2020-01-03 2020-01-04 2020-01-05
                    2020-01-06 2020-01-07 2020-01-08 2020-01-09 2020-01-10],
                 journal.postings.map(&:date).map(&:to_s)
    journal.postings.each do |posting|
      assert_kind_of String, posting.description
      assert !posting.description.empty?
    end
    assert_equal [2], journal.postings.map { |posting| posting.transfers.length }.uniq
    assert_equal ['$ 10.00'], journal.postings.map { |posting| posting.transfers[0].commodity.to_s }.uniq
    assert_equal ['Expense'], journal.postings.map { |posting| posting.transfers[0].account.to_s }.uniq
    assert_equal ['Cash'], journal.postings.map { |posting| posting.transfers[1].account.to_s }.uniq

    balance = RRA::Ledger.new.balance 'Expense', from_s: journal.to_s
    assert_equal 1, balance.accounts.length
    assert_equal 'Expense', balance.accounts[0].fullname
    assert_equal 1, balance.accounts[0].amounts.length
    assert_equal '$ 100.00', balance.accounts[0].amounts[0].to_s
  end

  def test_basic_cash_balance
    10.times.map { rand(1..10_000_000) }.each do |i|
      amount = format('$ %.2f', i.to_f / 100).to_commodity

      journal = RRA::Fakers::FakeJournal.basic_cash from: Date.new(2020, 1, 1), sum: amount

      assert_kind_of RRA::Journal, journal
      assert_equal(10, journal.postings.length)

      balance = RRA::Ledger.new.balance 'Expense', from_s: journal.to_s

      assert_equal 1, balance.accounts.length
      assert_equal 'Expense', balance.accounts[0].fullname
      assert_equal 1, balance.accounts[0].amounts.length
      assert_equal amount.to_s, balance.accounts[0].amounts[0].to_s
    end
  end

  def test_basic_cash_dates
    assert_equal %w[2020-01-01 2020-01-03 2020-01-05 2020-01-07 2020-01-09
                    2020-01-12 2020-01-14 2020-01-16 2020-01-18 2020-01-20],
                 RRA::Fakers::FakeJournal.basic_cash(from: Date.new(2020, 1, 1), to: Date.new(2020, 1, 20))
                                         .postings.map(&:date).map(&:to_s)

    assert_equal %w[2020-01-01 2020-02-09 2020-03-19 2020-04-28 2020-06-06
                    2020-07-16 2020-08-24 2020-10-03 2020-11-11 2020-12-20],
                 RRA::Fakers::FakeJournal.basic_cash(from: Date.new(2020, 1, 1), to: Date.new(2020, 12, 20))
                                         .postings.map(&:date).map(&:to_s)
  end

  def test_basic_cash_postings
    postings = [
      RRA::Journal::Posting.new(
        Date.new(2019, 12, 31), 'Posting from Dec 2019',
        transfers: [
        RRA::Journal::Posting::Transfer.new('Personal:Expenses:Testing', commodity: '$ 9.00'.to_commodity),
        RRA::Journal::Posting::Transfer.new('Cash')
        ]
      ),
      RRA::Journal::Posting.new(
        Date.new(2020, 2, 1), 'Posting from Feb 2020',
        transfers: [
        RRA::Journal::Posting::Transfer.new('Personal:Expenses:Testing', commodity: '$ 8.00'.to_commodity),
        RRA::Journal::Posting::Transfer.new('Cash')
        ]
      )
    ]

    journal = RRA::Fakers::FakeJournal.basic_cash from: Date.new(2020, 1, 1),
                                                  to: Date.new(2020, 1, 10),
                                                  postings: postings
    # Just make sure these postings are part of the output, and in the expected alphabetical order
    assert_equal 12, journal.postings.length

    assert_equal ['2019-12-31 Posting from Dec 2019',
                  '  Personal:Expenses:Testing    $ 9.00',
                  '  Cash'].join("\n"),
                 journal.postings.first.to_ledger
    assert_equal ['2020-02-01 Posting from Feb 2020',
                  '  Personal:Expenses:Testing    $ 8.00',
                  '  Cash'].join("\n"),
                 journal.postings.last.to_ledger
  end
end
