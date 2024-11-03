#!/usr/bin/env ruby
# frozen_string_literal: true

require 'time'
require 'minitest/autorun'

require_relative '../lib/rvgp'

# Tests for RVGP::Journal::Pricer
class TestPricer < Minitest::Test
  TEST_PRICES_DB_FORMAT1 = <<~DB_FORMAT1
    P 2004/06/25 00:00:00 FEQTX $24.00
    P 2004/06/21 02:18:01 FEQTX $22.49
    P 2004/06/21 02:18:01 BORL $6.20
    P 2004/06/21 02:18:02 AAPL $32.91
    P 2004/06/21 02:18:02 AU $400.00
    P 2004/06/21 14:15:00 FEQTX $ 22.75
    P 2004/06/25 01:00:00 BORL $6.20
    P 2004/06/25 02:00:00 AAPL $32.91
    P 2004/06/25 03:18:02 AU $400.00
  DB_FORMAT1

  TEST_PRICES_DB_FORMAT2 = <<~DB_FORMAT2
    P 2020-01-01 USD 0.893179 EUR
    P 2020-02-01 EUR 1.109275 USD
    P 2020-03-01 USD 0.907082  EUR
  DB_FORMAT2

  TEST_PRICES_LARGE_ASSETS = <<~LARGE_ASSETS
    P 2018/01/01 FLORIDAHOME  $500,000.00
    P 2018/01/01 CORVETTE  $50,000.00
  LARGE_ASSETS

  def test_price_format1
    p = RVGP::Journal::Pricer.new TEST_PRICES_DB_FORMAT1

    assert_raises(RVGP::Journal::Pricer::NoPriceError) { price_on p, '1900-01-01', 'FEQTX', 'USD' }
    assert_raises(RVGP::Journal::Pricer::NoPriceError) { price_on p, '2004-06-20', 'FEQTX', '$' }
    assert_raises(RVGP::Journal::Pricer::NoPriceError) { price_on p, '2004-06-21', 'FEQTX', 'USD' }

    assert_equal '$ 22.49', price_on(p, '2004-06-21 12:00:00', 'FEQTX', '$')
    assert_equal '$ 22.49', price_on(p, '2004-06-21 14:14:59', 'FEQTX', 'USD')
    assert_equal '$ 22.75', price_on(p, '2004-06-21 14:15:00', 'FEQTX', '$')
    assert_equal '$ 22.75', price_on(p, '2004-06-21 14:15:01', 'FEQTX', 'USD')
    assert_equal '$ 22.75', price_on(p, '2004-06-22', 'FEQTX', '$')
    assert_equal '$ 24.00', price_on(p, '2004-06-25', 'FEQTX', 'USD')
    assert_equal '$ 24.00', price_on(p, '2300-01-01', 'FEQTX', '$')

    # This is the same set of tests as above, but ,inverted:
    # Probably this doesn't make much sense in production, but, we use it with
    # fiat currencies later:
    assert_raises(RVGP::Journal::Pricer::NoPriceError) { price_on p, '1900-01-01', 'USD', 'FEQTX' }
    assert_raises(RVGP::Journal::Pricer::NoPriceError) { price_on p, '2004-06-20', '$', 'FEQTX' }
    assert_raises(RVGP::Journal::Pricer::NoPriceError) { price_on p, '2004-06-21', 'USD', 'FEQTX' }

    assert_equal '0.0444642063139173 FEQTX', price_on(p, '2004-06-21 12:00:00', 'USD', 'FEQTX')
    assert_equal '0.0444642063139173 FEQTX', price_on(p, '2004-06-21 14:14:59', '$', 'FEQTX')
    assert_equal '0.04395604395604396 FEQTX', price_on(p, '2004-06-21 14:15:00', 'USD', 'FEQTX')
    assert_equal '0.04395604395604396 FEQTX', price_on(p, '2004-06-21 14:15:01', '$', 'FEQTX')
    assert_equal '0.04395604395604396 FEQTX', price_on(p, '2004-06-22', 'USD', 'FEQTX')
    assert_equal '0.04166666666666667 FEQTX', price_on(p, '2004-06-25', '$', 'FEQTX')
    assert_equal '0.04166666666666667 FEQTX', price_on(p, '2300-01-01', 'USD', 'FEQTX')
  end

  def test_price_format2
    p = RVGP::Journal::Pricer.new TEST_PRICES_DB_FORMAT2

    assert_raises(RVGP::Journal::Pricer::NoPriceError) { price_on p, '2019-12-31', 'EUR', 'USD' }
    assert_raises(RVGP::Journal::Pricer::NoPriceError) { price_on p, '2019-12-31', 'USD', 'EUR' }

    assert_equal '1.11959640788688494 USD', price_on(p, '2020-01-01', 'EUR', 'USD')
    assert_equal '0.893179 EUR', price_on(p, '2020-01-01', 'USD', 'EUR')

    assert_equal '1.11959640788688494 USD', price_on(p, '2020-01-15', 'EUR', 'USD')
    assert_equal '0.893179 EUR', price_on(p, '2020-01-15', 'USD', 'EUR')

    assert_equal '1.109275 USD', price_on(p, '2020-02-01', 'EUR', 'USD')
    assert_equal '0.90148971174866467 EUR', price_on(p, '2020-02-01', 'USD', 'EUR')

    assert_equal '1.10243616343395636 USD', price_on(p, '2020-03-01', 'EUR', 'USD')
    assert_equal '0.907082 EUR', price_on(p, '2020-03-01', 'USD', 'EUR')

    assert_equal '1.10243616343395636 USD', price_on(p, '2020-03-01', 'EUR', 'USD')
    assert_equal '0.907082 EUR', price_on(p, '2020-03-15', 'USD', 'EUR')
  end

  def test_price_format3
    p = RVGP::Journal::Pricer.new TEST_PRICES_LARGE_ASSETS

    # Make sure the database is parsed ok:
    assert_equal '$ 500000.00', price_on(p, '2020-01-01 12:00:00', 'FLORIDAHOME', '$')
    assert_equal '$ 50000.00', price_on(p, '2020-01-01 12:00:00', 'CORVETTE', '$')

    # I don't think anyone will ever do this, but, why not:
    assert_equal '0.000002 FLORIDAHOME', price_on(p, '2020-01-01 12:00:00', '$', 'FLORIDAHOME')
    assert_equal '0.00002 CORVETTE', price_on(p, '2020-01-01 12:00:00', '$', 'CORVETTE')

    # And now get fancy with the conversions:
    at = Date.new(2020, 1, 1).to_time

    dollar = '$ 1.00'.to_commodity
    home = '1 FLORIDAHOME'.to_commodity
    minus_home = '-1 FLORIDAHOME'.to_commodity
    minus_dollar = '$ -1.00'.to_commodity

    assert_equal '$ 500000.00', p.convert(at, home, '$').to_s
    assert_equal '$ -500000.00', p.convert(at, minus_home, '$').to_s

    assert_equal '0.000002 FLORIDAHOME', p.convert(at, dollar, 'FLORIDAHOME').to_s
    assert_equal '-0.000002 FLORIDAHOME', p.convert(at, minus_dollar, 'FLORIDAHOME').to_s
  end

  def test_price_insert
    pricer = RVGP::Journal::Pricer.new
    pricer.add(Date.new(2020, 8, 1), 'ABC', '$ 0.80'.to_commodity)
    pricer.add(Date.new(2020, 1, 1), 'ABC', '0.10 USD'.to_commodity)
    pricer.add(Date.new(2020, 2, 1), 'ABC', '$0.20'.to_commodity)
    pricer.add(Date.new(2020, 3, 1), 'ABC', '0.30 USD'.to_commodity)
    pricer.add(Date.new(2020, 4, 1), 'ABC', '$0.40'.to_commodity)
    pricer.add(Date.new(2020, 6, 1), 'ABC', '0.60 USD'.to_commodity)
    pricer.add(Date.new(2020, 7, 1), 'ABC', '$0.70'.to_commodity)
    pricer.add(Date.new(2020, 5, 1), 'ABC', '0.50 USD'.to_commodity)

    assert_equal '0.10 USD', price_on(pricer, '2020-01-15', 'ABC', '$')
    assert_equal '$ 0.20',   price_on(pricer, '2020-02-15', 'ABC', '$')
    assert_equal '0.30 USD', price_on(pricer, '2020-03-15', 'ABC', '$')
    assert_equal '$ 0.40',   price_on(pricer, '2020-04-15', 'ABC', '$')
    assert_equal '0.50 USD', price_on(pricer, '2020-05-15', 'ABC', '$')
    assert_equal '0.60 USD', price_on(pricer, '2020-06-15', 'ABC', '$')
    assert_equal '$ 0.70',   price_on(pricer, '2020-07-15', 'ABC', '$')
    assert_equal '$ 0.80',   price_on(pricer, '2020-08-15', 'ABC', '$')
  end

  def test_price_insert_swapped_pairs
    # This looks like a bug that cropped up in production. Whereby, the key pairs
    # are reversed in subsequent calls, and we're unable to handle that case.
    # There's no reason this shouldn't work like TEST_PRICES_DB_FORMAT2.
    p = RVGP::Journal::Pricer.new <<~SWAPPED_PRICES
      P 2010-01-01 USD 3808 COP
      P 2010-02-01 USD 4063.75 COP
    SWAPPED_PRICES

    # This is equivalent to adding the following, in the above prices_db:
    #    P 2010-03-01 COP $ 0.00025
    p.add(Date.new(2010, 3, 1), 'COP', '$ 0.00025'.to_commodity)

    assert_equal '3808.00 COP', price_on(p, '2010-01-15', '$', 'COP')
    assert_equal '4063.75 COP', price_on(p, '2010-02-15', '$', 'COP')
    assert_equal '4000.00 COP', price_on(p, '2010-03-15', '$', 'COP')
  end

  private

  def price_on(pricer, date_str, code_from, code_to)
    pricer.price(Time.parse(date_str), code_from, code_to).to_s
  end
end
