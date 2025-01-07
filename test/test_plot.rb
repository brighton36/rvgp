#!/usr/bin/env ruby
# frozen_string_literal: true

require 'csv'
require 'minitest/autorun'

require_relative '../lib/rvgp'
require_relative '../lib/rvgp/plot'

# Tests for RVGP::Plot
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
  ].freeze

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
  ].freeze

  def test_globber
    # NOTE: I'm testing the %<key>s here, in addition to %{key}. But, really, the later is probably whats
    # preferred....
    globs = RVGP::Plot::Glob.variants '%<year>s-wealth-growth.csv', YEAR_ONLY_CORPUS

    assert_equal 5, globs.length

    2018.upto(2018 + 4).each_with_index.map do |year, i|
      assert_equal [format('/path/to/ledger/%d-wealth-growth.csv', year)], globs[i].files
      assert_equal format('%d-wealth-growth', year), globs[i].name
      assert_equal({ year: year.to_s }, globs[i].values)
    end

    globs = RVGP::Plot::Glob.variants '%<year>s-cashflow-%{intention}.csv', YEAR_AND_INTENTION_CORPUS # rubocop:disable Style/FormatStringToken

    assert_equal 9, globs.length

    assert_equal ['build/grids/2018-cashflow-burgershop.csv'], globs[0].files
    assert_equal '2018-cashflow-burgershop', globs[0].name
    assert_equal({ year: '2018', intention: 'burgershop' }, globs[0].values)

    assert_equal ['build/grids/2018-cashflow-multiplex.csv'], globs[1].files
    assert_equal '2018-cashflow-multiplex', globs[1].name
    assert_equal({ year: '2018', intention: 'multiplex' }, globs[1].values)

    assert_equal ['build/grids/2018-cashflow-ignored.csv'], globs[2].files
    assert_equal '2018-cashflow-ignored', globs[2].name
    assert_equal({ year: '2018', intention: 'ignored' }, globs[2].values)

    assert_equal ['build/grids/2018-cashflow-personal.csv'], globs[3].files
    assert_equal '2018-cashflow-personal', globs[3].name
    assert_equal({ year: '2018', intention: 'personal' }, globs[3].values)

    assert_equal ['build/grids/2018-cashflow-frozenbananastand.csv'], globs[4].files
    assert_equal '2018-cashflow-frozenbananastand', globs[4].name
    assert_equal({ year: '2018', intention: 'frozenbananastand' }, globs[4].values)

    assert_equal ['build/grids/2019-cashflow-burgershop.csv'], globs[5].files
    assert_equal '2019-cashflow-burgershop', globs[5].name
    assert_equal({ year: '2019', intention: 'burgershop' }, globs[5].values)

    assert_equal ['build/grids/2019-cashflow-multiplex.csv'], globs[6].files
    assert_equal '2019-cashflow-multiplex', globs[6].name
    assert_equal({ year: '2019', intention: 'multiplex' }, globs[6].values)

    assert_equal ['build/grids/2019-cashflow-ignored.csv'], globs[7].files
    assert_equal '2019-cashflow-ignored', globs[7].name
    assert_equal({ year: '2019', intention: 'ignored' }, globs[7].values)

    assert_equal ['build/grids/2019-cashflow-personal.csv'], globs[8].files
    assert_equal '2019-cashflow-personal', globs[8].name
    assert_equal({ year: '2019', intention: 'personal' }, globs[8].values)
  end

  def test_all_year_globber
    globs = RVGP::Plot::Glob.variants '%<year>s-wealth-growth.csv', YEAR_ONLY_CORPUS, [:year]

    assert_equal 1, globs.length

    assert_equal ['/path/to/ledger/2018-wealth-growth.csv',
                  '/path/to/ledger/2019-wealth-growth.csv',
                  '/path/to/ledger/2020-wealth-growth.csv',
                  '/path/to/ledger/2021-wealth-growth.csv',
                  '/path/to/ledger/2022-wealth-growth.csv'], globs[0].files
    assert_equal 'all-wealth-growth', globs[0].name
    assert_equal({ year: true }, globs[0].values)

    globs = RVGP::Plot::Glob.variants '%<year>s-cashflow-%{intention}.csv', YEAR_AND_INTENTION_CORPUS, [:year] # rubocop:disable Style/FormatStringToken

    assert_equal 5, globs.length

    assert_equal(%w[2018 2019].map { |y| format('build/grids/%s-cashflow-burgershop.csv', y) }, globs[0].files)
    assert_equal 'all-cashflow-burgershop', globs[0].name
    assert_equal({ year: true, intention: 'burgershop' }, globs[0].values)

    assert_equal(%w[2018 2019].map { |y| format('build/grids/%s-cashflow-multiplex.csv', y) }, globs[1].files)
    assert_equal 'all-cashflow-multiplex', globs[1].name
    assert_equal({ year: true, intention: 'multiplex' }, globs[1].values)

    assert_equal(%w[2018 2019].map { |y| format('build/grids/%s-cashflow-ignored.csv', y) }, globs[2].files)
    assert_equal 'all-cashflow-ignored', globs[2].name
    assert_equal({ year: true, intention: 'ignored' }, globs[2].values)

    assert_equal(%w[2018 2019].map { |y| format('build/grids/%s-cashflow-personal.csv', y) }, globs[3].files)
    assert_equal 'all-cashflow-personal', globs[3].name
    assert_equal({ year: true, intention: 'personal' }, globs[3].values)

    assert_equal ['build/grids/2018-cashflow-frozenbananastand.csv'], globs[4].files
    assert_equal 'all-cashflow-frozenbananastand', globs[4].name
    assert_equal({ year: true, intention: 'frozenbananastand' }, globs[4].values)
  end

  def test_invalid_glob
    assert RVGP::Plot::Glob.valid?('%<year>s-cashflow.csv')
    assert RVGP::Plot::Glob.valid?('%{year}s-cashflow.csv') # rubocop:disable Style/FormatStringToken
    assert !RVGP::Plot::Glob.valid?('%<basename>s-cashflow.csv')
    assert !RVGP::Plot::Glob.valid?('%<values>s-cashflow.csv')
    assert !RVGP::Plot::Glob.valid?('%{keys}-cashflow.csv') # rubocop:disable Style/FormatStringToken
    assert !RVGP::Plot::Glob.valid?('%{files}-cashflow.csv') # rubocop:disable Style/FormatStringToken
  end
end
