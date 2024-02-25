#!/usr/bin/env ruby
# frozen_string_literal: true

require 'date'
require 'minitest/autorun'

require_relative '../lib/rvgp'
require_relative '../lib/rvgp/journal'

# Tests for RVGP::Journal::Posting
class TestPosting < Minitest::Test
  def test_posting_to_ledger
    posting = RVGP::Journal::Posting.new(
      Date.new(2021, 10, 2),
      'Heroes R Us',
      tags: ['Vacation: Seattle'.to_tag],
      transfers: [
        ['Expenses:Comics', { commodity: '$ 5.00'.to_commodity, tags: ['Publisher: Marvel'.to_tag] }],
        ['Expenses:Cards', { commodity: '$ 9.00'.to_commodity, tags: ['Collection: Baseball'.to_tag] }],
        ['Cash']
      ].collect { |args| RVGP::Journal::Posting::Transfer.new(*args) }
    )

    assert_equal [
      '2021-10-02 Heroes R Us',
      '  ; Vacation: Seattle',
      '  Expenses:Comics    $ 5.00',
      '  ; Publisher: Marvel',
      '  Expenses:Cards     $ 9.00',
      '  ; Collection: Baseball',
      '  Cash'
    ].join("\n"), posting.to_ledger
  end

  def test_posting_with_complex_commodity_to_ledger
    complex_commodity = RVGP::Journal::ComplexCommodity.from_s(['-1000.0001 VBTLX', '@@', '$ 100000.00'].join(' '))

    posting = RVGP::Journal::Posting.new(
      '2022-03-28',
      'VANGUARD TOTAL BOND MARKET INDEX Sell',
      transfers: [RVGP::Journal::Posting::Transfer.new('Personal:Assets:Vanguard:VBTLX', commodity: complex_commodity),
                  RVGP::Journal::Posting::Transfer.new('Personal:Assets:Vanguard:MoneyMarket')]
    )

    assert_equal ['2022-03-28 VANGUARD TOTAL BOND MARKET INDEX Sell',
                  '  Personal:Assets:Vanguard:VBTLX    -1000.0001 VBTLX @@ $ 100000.00',
                  '  Personal:Assets:Vanguard:MoneyMarket'].join("\n"),
                 posting.to_ledger
  end
end
