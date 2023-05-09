#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'

require_relative '../lib/rra'
require_relative '../lib/rra/fakers/fake_feed'

# Minitest class, used to test RRA::Fakers::FakeJournal
class TestFakeFeed < Minitest::Test
  def test_basic_feed
    feed = RRA::Fakers::FakeFeed.basic_checking from: Date.new(2020, 1, 1),
                                                to: Date.new(2020, 3, 31),
                                                post_count: 300

    assert_kind_of String, feed

    csv = CSV.parse feed, headers: true
    assert_equal 300, csv.length

    assert_equal ['Date', 'Type', 'Description', 'Withdrawal (-)', 'Deposit (+)',
                  'RunningBalance'], csv.headers
    assert_equal '01/01/2020', csv.first['Date']
    assert_equal '03/31/2020', csv[-1]['Date']

    csv.each do |row|
      assert_kind_of String, row['Date']
      assert_kind_of String, row['Type']
      assert_kind_of String, row['Description']
      assert_kind_of String, row['Withdrawal (-)']
      assert_kind_of String, row['Deposit (+)']
      assert_kind_of String, row['RunningBalance']

      assert_match(/\A\d{2}\/\d{2}\/\d{4}\Z/, row['Date'])
      assert !row['Type'].empty?
      assert !row['Description'].empty?
      assert_match(/\$ \d+\.\d{2}/,
                   row['Withdrawal (-)'].empty? ? row['Deposit (+)'] : row['Withdrawal (-)'])
      assert_match(/\$ -?\d+\.\d{2}/, row['RunningBalance'])
    end
  end

  def test_companies_param
    companies = %w(Walmart Amazon Apple CVS Exxon Berkshire Google Microsoft Costco)
    feed = RRA::Fakers::FakeFeed.basic_checking post_count: 50, companies: companies

    csv = CSV.parse feed, headers: true
    assert_equal 50, csv.length
    csv.each do |row|
      company = row['Description']
      company = ::Regexp.last_match 1 if /\A(.+) DIRECT DEP\Z/.match company
      assert_includes companies, company
    end
  end
end
