#!/usr/bin/env ruby

require "csv"
require "minitest/autorun"

require_relative '../lib/rra'
require_relative '../lib/rra/plot'

class TestPlot < Minitest::Test
  YEAR_ONLY_CORPUS = [
    '/path/to/ledger/2018-wealth-growth.csv',
    '/path/to/ledger/2019-wealth-growth.csv', 
    '/path/to/ledger/2020-wealth-growth.csv',
    '/path/to/ledger/2021-wealth-growth.csv', 
    '/path/to/ledger/2022-wealth-growth.csv',
    # These are meant to be ignored:
    '/path/to/ledger/2018-profit-and-loss.csv',
    '/path/to/ledger/2019-profit-and-loss.csv', 
    '/path/to/ledger/2020-profit-and-loss.csv', 
    '/path/to/ledger/2021-profit-and-loss.csv' 
  ]

  YEAR_AND_INTENTION_CORPUS = [
    'build/grids/2018-cashflow-burgershop.csv',
    'build/grids/2018-cashflow-multiplex.csv',
    'build/grids/2018-cashflow-ignored.csv',
    'build/grids/2018-cashflow-personal.csv',
    # NOTE: We sold the frozenbananastand in 2018, so, there's no 2019 grid
    'build/grids/2018-cashflow-frozenbananastand.csv',
    'build/grids/2019-cashflow-burgershop.csv',
    'build/grids/2019-cashflow-multiplex.csv',
    'build/grids/2019-cashflow-ignored.csv',
    'build/grids/2019-cashflow-personal.csv',
    # These are meant to be ignored:
    '/path/to/ledger/2018-profit-and-loss.csv', 
    '/path/to/ledger/2019-profit-and-loss.csv', 
    '/path/to/ledger/2020-profit-and-loss.csv', 
    '/path/to/ledger/2021-profit-and-loss.csv' 
  ]

  def test_globber
    matches = RRA::Plot.glob_variants '%{year}-wealth-growth.csv', 
      YEAR_ONLY_CORPUS

    assert_equal 5, matches.length

    0.upto(4).collect do |i| 
      year = 2018+i
      assert_equal [ '/path/to/ledger/%d-wealth-growth.csv' % [year] ], 
        matches[i][:files]
      assert_equal '%d-wealth-growth' % [year], matches[i][:name]
      assert_equal( {year: year.to_s}, matches[i][:pairs] )
    end

    matches = RRA::Plot.glob_variants '%{year}-cashflow-%{intention}.csv', 
      YEAR_AND_INTENTION_CORPUS

    assert_equal 9, matches.length

    assert_equal ['build/grids/2018-cashflow-burgershop.csv'], matches[0][:files]
    assert_equal '2018-cashflow-burgershop', matches[0][:name]
    assert_equal( {year: '2018', intention: 'burgershop'}, matches[0][:pairs] )
    
    assert_equal ['build/grids/2018-cashflow-multiplex.csv'], matches[1][:files]
    assert_equal '2018-cashflow-multiplex', matches[1][:name]
    assert_equal( {year: '2018', intention: 'multiplex'}, matches[1][:pairs] )

    assert_equal ['build/grids/2018-cashflow-ignored.csv'], matches[2][:files]
    assert_equal '2018-cashflow-ignored', matches[2][:name]
    assert_equal( {year: '2018', intention: 'ignored'}, matches[2][:pairs] )

    assert_equal ['build/grids/2018-cashflow-personal.csv'], matches[3][:files]
    assert_equal '2018-cashflow-personal', matches[3][:name]
    assert_equal( {year: '2018', intention: 'personal'}, matches[3][:pairs] )

    assert_equal ['build/grids/2018-cashflow-frozenbananastand.csv'], matches[4][:files]
    assert_equal '2018-cashflow-frozenbananastand', matches[4][:name]
    assert_equal( {year: '2018', intention: 'frozenbananastand'}, matches[4][:pairs] )

    assert_equal ['build/grids/2019-cashflow-burgershop.csv'], matches[5][:files]
    assert_equal '2019-cashflow-burgershop', matches[5][:name]
    assert_equal( {year: '2019', intention: 'burgershop'}, matches[5][:pairs] )
    
    assert_equal ['build/grids/2019-cashflow-multiplex.csv'], matches[6][:files]
    assert_equal '2019-cashflow-multiplex', matches[6][:name]
    assert_equal( {year: '2019', intention: 'multiplex'}, matches[6][:pairs] )

    assert_equal ['build/grids/2019-cashflow-ignored.csv'], matches[7][:files]
    assert_equal '2019-cashflow-ignored', matches[7][:name]
    assert_equal( {year: '2019', intention: 'ignored'}, matches[7][:pairs] )

    assert_equal ['build/grids/2019-cashflow-personal.csv'], matches[8][:files]
    assert_equal '2019-cashflow-personal', matches[8][:name]
    assert_equal( {year: '2019', intention: 'personal'}, matches[8][:pairs] )
  end

  def test_all_year_globber
    matches = RRA::Plot.glob_variants '%{year}-wealth-growth.csv',
      YEAR_ONLY_CORPUS, year: 'all'

    assert_equal 1, matches.length

    assert_equal [ '/path/to/ledger/2018-wealth-growth.csv',
    '/path/to/ledger/2019-wealth-growth.csv', 
    '/path/to/ledger/2020-wealth-growth.csv',
    '/path/to/ledger/2021-wealth-growth.csv', 
    '/path/to/ledger/2022-wealth-growth.csv'], matches[0][:files]
    assert_equal 'all-wealth-growth', matches[0][:name]
    assert_equal( {year: 'all'}, matches[0][:pairs] )

    matches = RRA::Plot.glob_variants '%{year}-cashflow-%{intention}.csv', 
      YEAR_AND_INTENTION_CORPUS, year: 'all'

    assert_equal 5, matches.length

    assert_equal(
      %w(2018 2019).collect{|y| 'build/grids/%s-cashflow-burgershop.csv' % y},
      matches[0][:files] )
    assert_equal 'all-cashflow-burgershop', matches[0][:name]
    assert_equal( {year: 'all', intention: 'burgershop'}, matches[0][:pairs] )

    assert_equal(
      %w(2018 2019).collect{|y| 'build/grids/%s-cashflow-multiplex.csv' % y},
      matches[1][:files])
    assert_equal 'all-cashflow-multiplex', matches[1][:name]
    assert_equal( {year: 'all', intention: 'multiplex'}, matches[1][:pairs] )

    assert_equal(
      %w(2018 2019).collect{|y| 'build/grids/%s-cashflow-ignored.csv' % y},
      matches[2][:files])
    assert_equal 'all-cashflow-ignored', matches[2][:name]
    assert_equal( {year: 'all', intention: 'ignored'}, matches[2][:pairs] )

    assert_equal(
      %w(2018 2019).collect{|y| 'build/grids/%s-cashflow-personal.csv' % y},
      matches[3][:files])
    assert_equal 'all-cashflow-personal', matches[3][:name]
    assert_equal( {year: 'all', intention: 'personal'}, matches[3][:pairs] )

    assert_equal ['build/grids/2018-cashflow-frozenbananastand.csv'], matches[4][:files]
    assert_equal 'all-cashflow-frozenbananastand', matches[4][:name]
    assert_equal( {year: 'all', intention: 'frozenbananastand'}, matches[4][:pairs] )
  end
end
