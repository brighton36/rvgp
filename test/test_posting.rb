#!/usr/bin/env ruby

require 'date'
require "minitest/autorun"

require_relative '../lib/rra'
require_relative '../lib/rra/journal'

class TestPosting < Minitest::Test
  def test_posting_to_ledger
    posting = RRA::Journal::Posting.new(Date.new(2021, 10, 2), "Heroes R Us", 
      tags: [ 'Vacation: Seattle'.to_tag ],
      transfers: [ 
        [ 'Expenses:Comics', 
          {commodity: '$ 5.00'.to_commodity, tags: ['Publisher: Marvel'.to_tag]}
        ],
        [ 'Expenses:Cards', 
          {commodity: '$ 9.00'.to_commodity, tags: ['Collection: Baseball'.to_tag]}
        ],
        [ 'Cash' ]
      ].collect{|args| RRA::Journal::Posting::Transfer.new(*args)})

    assert_equal ["2021-10-02 Heroes R Us",
     "  ; Vacation: Seattle",
     "  Expenses:Comics    $ 5.00",
     "  ; Publisher: Marvel",
     "  Expenses:Cards     $ 9.00",
     "  ; Collection: Baseball",
     "  Cash"].join("\n"), posting.to_ledger
  end
end
