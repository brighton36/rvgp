#!/usr/bin/env ruby
# frozen_string_literal: true

require 'csv'
require 'minitest/autorun'

require_relative '../lib/rvgp'

# These tests ensure that RVGP::Pta::Ledger parses the xml output, as we'd expect.
# Atm, most of these tests are in a private repo, since they test 'my' output,
# that I can't share. However, as this projects is becoming public, we now have
# the ability to start running these tests against faker output. So, for the time
# being, I'm porting my personal tests over to faker/public tests. And what's here,
# is a subset of that suite.
class TestLedger < Minitest::Test
  def test_balance_multiple_with_empty
    # We'll use this feature here:
    opts = { translate_meta_accounts: true }

    # This command was used to produce the ledger_total_monthly_liabilities_with_empty.xml:
    # note the '--empty', which, forces the output to include all months in the range, even
    # when there's no activity in a given month:
    #
    #   /usr/bin/ledger xml Liabilities --sort date --monthly --empty \
    #     --file /tmp/test_ledger/test-user.journal --collapse --display 'date>=[2020-01-01]' \
    #     --end 2020-12-31 > ledger_total_monthly_liabilities_with_empty.xml
    #
    # This table came by running  the above ledger command as 'reg' instead of 'xml', and adjusting cell 0 to use
    # the date format we generate
    assert_register [
      ['2020-01-01', '- 20-Jan-31', nil,                                    '0',        '$ -10675.18'],
      ['2020-02-01', '- 20-Feb-29', 'Personal:Liabilities:AmericanExpress', '$ 303.72', '$ -10371.46'],
      ['2020-03-01', '- 20-Mar-31', nil,                                    '0',        '$ -10371.46'],
      ['2020-04-01', '- 20-Apr-30', 'Personal:Liabilities:AmericanExpress', '$ 661.01', '$ -9710.45'],
      ['2020-05-01', '- 20-May-31', 'Personal:Liabilities:AmericanExpress', '$ 912.36', '$ -8798.09'],
      ['2020-06-01', '- 20-Jun-30', 'Personal:Liabilities:AmericanExpress', '$ 322.98', '$ -8475.11'],
      ['2020-07-01', '- 20-Jul-31', 'Personal:Liabilities:AmericanExpress', '$ 279.26', '$ -8195.85'],
      ['2020-08-01', '- 20-Aug-31', nil,                                    '0',        '$ -8195.85'],
      ['2020-09-01', '- 20-Sep-30', 'Personal:Liabilities:AmericanExpress', '$ 330.54', '$ -7865.31'],
      ['2020-10-01', '- 20-Oct-31', nil,                                    '0',        '$ -7865.31'],
      ['2020-11-01', '- 20-Nov-30', 'Personal:Liabilities:AmericanExpress', '$ 262.42', '$ -7602.89']
      # NOTE: We're missing december's output, from ledger. This is... 'the bug' that necessitated switching
      # from --end to --display , in the reduce_postings_by_month
    ], RVGP::Pta::Ledger::Output::Register.new(asset_contents('ledger_total_monthly_liabilities_with_empty.xml'), opts)

    # This is really no different than the above register, other than the values are different, I guess
    #
    #   /usr/bin/ledger reg Income --sort date --monthly --empty \
    #   --file /tmp/test_ledger/ronnie-peterson.journal --collapse --begin 2023-01-01 \
    #   --end 2023-12-31 > 'ledger_total_monthly_liabilities_with_empty2.xml'
    #
    assert_register [
      ['2023-01-01', '- 23-Jan-31', 'Personal:Income:ThompsonHegmann',   '$ -5565.74',  '$ -5565.74'],
      ['2023-02-01', '- 23-Feb-28', :total,                              '$ -18028.51', '$ -23594.25'],
      ['2023-03-01', '- 23-Mar-31', nil,                                 '0',           '$ -23594.25'],
      ['2023-04-01', '- 23-Apr-30', 'Personal:Income:VonRuedenMosciski', '$ -5356.77',  '$ -28951.02'],
      ['2023-05-01', '- 23-May-31', 'Personal:Income:ThompsonHegmann',   '$ -12371.24', '$ -41322.26'],
      ['2023-06-01', '- 23-Jun-30', 'Personal:Income:ThompsonHegmann',   '$ -6075.64',  '$ -47397.90'],
      ['2023-07-01', '- 23-Jul-31', nil,                                 '0',           '$ -47397.90'],
      ['2023-08-01', '- 23-Aug-31', 'Personal:Income:VonRuedenMosciski', '$ -5784.12',  '$ -53182.02'],
      ['2023-09-01', '- 23-Sep-30', nil,                                 '0',           '$ -53182.02'],
      ['2023-10-01', '- 23-Oct-31', nil,                                 '0',           '$ -53182.02'],
      ['2023-11-01', '- 23-Nov-30', 'Personal:Income:ThompsonHegmann',   '$ -5485.09',  '$ -58667.11'],
      ['2023-12-01', '- 23-Dec-31', 'Personal:Income:ThompsonHegmann',   '$ -6297.26',  '$ -64964.37']
    ], RVGP::Pta::Ledger::Output::Register.new(asset_contents('ledger_total_monthly_liabilities_with_empty2.xml'), opts)
  end

  private

  def assert_register(expectations, register)
    assert_equal expectations.length, register.transactions.length

    # First:
    0.upto(expectations.length - 1) do |i|
      assert_equal expectations[i][0], register.transactions[i].date.to_s
      assert_equal expectations[i][1], register.transactions[i].payee
      assert_equal 1, register.transactions[i].postings.length
      if expectations[i][2].nil?
        assert_nil register.transactions[i].postings[0].account
      else
        assert_equal expectations[i][2], register.transactions[i].postings[0].account
      end
      assert_equal 1, register.transactions[i].postings[0].amounts.length
      assert_equal expectations[i][3], register.transactions[i].postings[0].amounts.first.to_s
      assert_equal 1, register.transactions[i].postings[0].totals.length
      assert_equal expectations[i][3], register.transactions[i].postings[0].amounts.first.to_s
      assert_equal expectations[i][4], register.transactions[i].postings[0].totals.first.to_s
      amount_in_usd = register.transactions[i].postings[0].amount_in('$')
      if amount_in_usd.nil?
        assert_equal '0', expectations[i][3].to_s
      else
        assert_equal amount_in_usd.to_s, register.transactions[i].postings[0].amount_in('$').to_s
      end
      assert_equal expectations[i][4], register.transactions[i].postings[0].total_in('$').to_s
      assert_equal({}, register.transactions[i].postings[0].tags)
    end
  end

  def asset_contents(filename)
    File.read [File.dirname(__FILE__), 'assets', filename].join('/')
  end
end
