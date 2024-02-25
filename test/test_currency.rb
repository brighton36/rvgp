#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'

require_relative '../lib/rvgp'

# Minitest class, used to test RRA::Journal::Currency
class TestCurrency < Minitest::Test
  def test_currency
    currency = RRA::Journal::Currency.from_code_or_symbol 'USD'
    assert_equal 'UNITED STATES', currency.entity
    assert_equal 'US Dollar', currency.currency
    assert_equal 'USD', currency.alphabetic_code
    assert_equal 840, currency.numeric_code
    assert_equal 2, currency.minor_unit
    assert_equal '$', currency.symbol
  end

  def test_currency_nil
    currency = RRA::Journal::Currency.from_code_or_symbol nil
    assert_nil nil, currency
  end
end
