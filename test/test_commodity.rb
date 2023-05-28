#!/usr/bin/env ruby

require "minitest/autorun"

require_relative '../lib/rra'

class TestCommodity < Minitest::Test
  def test_commodity_comparision_when_precision_not_equal
    assert_equal commodity("$ 23.01"), commodity("$ 23.010")
    assert_equal commodity("$ 23.010"), commodity("$ 23.01")

    assert_equal commodity("$ 23.010"), commodity("$ 23.01")
    assert_equal commodity("$ 23.01"), commodity("$ 23.010")

    assert_equal commodity("$ 23.00"), commodity("$ 23.000000")
    assert_equal commodity("$ 23.000000"), commodity("$ 23.00")

    assert(commodity("$ 13.000") != commodity("$ 23.00"))
    assert(commodity("$ 23.00") != commodity("$ 13.000"))

    assert(commodity("$ 23.00") != commodity("$ 13.000"))
    assert(commodity("$ 13.000") != commodity("$ 23.00"))
  end

  def test_commodity_add_and_sub_when_precision_not_equal
    assert_equal '$ 32.00', commodity_op("$ 2", :+, "$ 30")
    assert_equal '$ 25.01', commodity_op("$ 24.01", :+, "$ 1")
    assert_equal '$ 46.02', commodity_op("$ 23.01", :+, "$ 23.010")
    assert_equal '$ 15.01002', commodity_op("$ 5.000020", :+, "$ 10.010")
    assert_equal '$ 110.00001', commodity_op("$ 10.000004", :+, "$ 100.000006")
    assert_equal '$ 15.20', commodity_op("$ 5.1", :+, "$ 10.1")
    assert_equal '$ 15.10', commodity_op("$ 5.10", :+, "$ 10")
    assert_equal '$ 10.01', commodity_op("$ 5.005", :+, "$ 5.005")

    assert_equal '$ 0.00', commodity_op("$ 1", :-, '$ 1')
    assert_equal '$ 1.9996', commodity_op("$ 3.0009", :-, '$ 1.0013')
    assert_equal '$ -1.00', 
      commodity_op("$ 1.000000000000001", :-, '$ 2.000000000000001')
    assert_equal '$ 0.10', commodity_op("$ 0.2", :-, '$ 0.1')
    assert_equal '$ 0.01', commodity_op("$ 0.02", :-, '$ 0.01')
    assert_equal '$ 0.05', commodity_op("$ 0.1", :-, '$ 0.05')
    assert_equal '$ 0.90', commodity_op("$ 1.0", :-, '$ 0.1')
    assert_equal '$ 0.99', commodity_op("$ 1.0", :-, '$ 0.01')

    assert_equal '$ -0.10', commodity_op("$ -0.2", :-, '$ -0.1')
    assert_equal '$ -0.01', commodity_op("$ -0.02", :-, '$ -0.01')
    assert_equal '$ -0.05', commodity_op("$ -0.1", :-, '$ -0.05')
    assert_equal '$ -0.90', commodity_op("$ -1.0", :-, '$ -0.1')
    assert_equal '$ -0.99', commodity_op("$ -1.0", :-, '$ -0.01')

    assert_equal '$ -0.30', commodity_op("$ -0.2", :-, '$ 0.1')
    assert_equal '$ -0.03', commodity_op("$ -0.02", :-, '$ 0.01')
    assert_equal '$ -0.15', commodity_op("$ -0.1", :-, '$ 0.05')
    assert_equal '$ -1.10', commodity_op("$ -1.0", :-, '$ 0.1')
    assert_equal '$ -1.01', commodity_op("$ -1.0", :-, '$ 0.01')

    assert_equal '$ 0.30', commodity_op("$ 0.2", :-, '$ -0.1')
    assert_equal '$ 0.03', commodity_op("$ 0.02", :-, '$ -0.01')
    assert_equal '$ 0.15', commodity_op("$ 0.1", :-, '$ -0.05')
    assert_equal '$ 1.10', commodity_op("$ 1.0", :-, '$ -0.1')
    assert_equal '$ 1.01', commodity_op("$ 1.0", :-, '$ -0.01')
  end

  def test_sum
    assert_equal commodity('$ 100.00'), 
      ["$ 22.00", "$ 60.00", "$ 8.00", "$ 10.00"].collect{|s| commodity s}.sum
  end

  def test_commodity_mul_by_numeric
    assert_equal commodity('$ 32.00'), commodity("$ 2") * 16
    assert_equal commodity('$ 17.00'), commodity("$ 2") * 8.5
    assert_equal commodity('$ 2.00'), commodity("$ 0.5") * 4

    assert_equal commodity('$ -32.00'), commodity("$ -2") * 16
    assert_equal commodity('$ -17.00'), commodity("$ -2") * 8.5
    assert_equal commodity('$ -2.00'), commodity("$ -0.5") * 4

    assert_equal commodity('$ -32.00'), commodity("$ 2") * -16
    assert_equal commodity('$ -17.00'), commodity("$ 2") * -8.5
    assert_equal commodity('$ -2.00'), commodity("$ 0.5") * -4

    assert_equal commodity('$ 0.5000125'), commodity("$ 2.00005") * 0.25
    assert_equal commodity('$ 0.5000125'), commodity("$ 0.25") * 2.00005
  end

  def test_commodity_div_by_numeric
    assert_equal commodity("$ 2"), commodity('$ 32.00') / 16
    assert_equal commodity("$ 2"), commodity('$ 17.00') / 8.5
    assert_equal commodity("$ 0.5"), commodity('$ 2.00') / 4

    assert_equal commodity("$ -2"), commodity('$ -32.00') / 16
    assert_equal commodity("$ -2"), commodity('$ -17.00') / 8.5
    assert_equal commodity("$ -0.5"), commodity('$ -2.00') / 4

    assert_equal commodity("$ 2"), commodity('$ -32.00') / -16
    assert_equal commodity("$ 2"), commodity('$ -17.00') / -8.5
    assert_equal commodity("$ 0.5"), commodity('$ -2.00') / -4

    assert_equal commodity("$ 2.00005"), commodity('$ 0.5000125') / 0.25
    assert_equal commodity("$ 0.25"), commodity('$ 0.5000125') / 2.00005
    assert_equal commodity("$ 0.005"), commodity('$ 0.01') / 2
  end

  def test_huge_decimal_sum_when_decimal_zeros
    # This bug showed up while testing the HLedger::balance ...
    assert_equal '$ 493.00', [
      '$ 443.0000000000'.to_commodity, '$ 50.0000000000'.to_commodity].sum.to_s
    assert_equal '$ 493.10', [
      '$ 443.0500000000'.to_commodity, '$ 50.0500000000'.to_commodity].sum.to_s
    assert_equal '$ 0.00', [
      '$ 0.0000000000'.to_commodity, '$ 0.0000000000'.to_commodity].sum.to_s
  end

  def test_round
    assert_equal '$ 123.46', '$ 123.455'.to_commodity.round(2).to_s
    assert_equal '$ -123.46', '$ -123.455'.to_commodity.round(2).to_s
    assert_equal '$ 123.46', '$ 123.459999999999'.to_commodity.round(2).to_s
    assert_equal '$ 123.454545', '$ 123.4545454545454'.to_commodity.round(6).to_s
    assert_equal '$ -123.46', '$ -123.459999999999'.to_commodity.round(2).to_s
    assert_equal '$ 123.45', '$ 123.454444449'.to_commodity.round(2).to_s
    assert_equal '$ -123.45', '$ -123.454444449'.to_commodity.round(2).to_s
    assert_equal '$ 123.44', '$ 123.44'.to_commodity.round(2).to_s
    assert_equal '$ -123.44', '$ -123.44'.to_commodity.round(2).to_s
    assert_equal '$ 123.4000', '$ 123.4'.to_commodity.round(4).to_s
    assert_equal '$ -123.4000', '$ -123.4'.to_commodity.round(4).to_s
    assert_equal '$ 123.0000', '$ 123'.to_commodity.round(4).to_s
    assert_equal '$ -123.0000', '$ -123'.to_commodity.round(4).to_s
    assert_equal '$ 123', '$ 123.0455555555'.to_commodity.round(0).to_s
    assert_equal '$ -123', '$ -123.0455555555'.to_commodity.round(0).to_s
    assert_equal '$ 1000.00', '$ 999.99999'.to_commodity.round(2).to_s
    assert_equal '$ -1000.00', '$ -999.99999'.to_commodity.round(2).to_s

    assert_equal '$ 123.45', '$ 123.454'.to_commodity.round(2).to_s
    assert_equal '$ -123.45', '$ -123.454'.to_commodity.round(2).to_s

    # Found/fixed on 2021-10-25:
    assert_equal '$ 2584.09', '$ 2584.09'.to_commodity.round(2).to_s
    assert_equal '$ 2584.009', '$ 2584.009'.to_commodity.round(3).to_s
    assert_equal '$ 2584.009', '$ 2584.009'.to_commodity.round(3).to_s
    assert_equal '$ 2584.900', '$ 2584.900'.to_commodity.round(3).to_s
    assert_equal '$ 2584.9', '$ 2584.9'.to_commodity.round(1).to_s

    # Found/fixed on 2022-11-13:
    # The reason this is a bug, is because the mantissa begins with zero's. We
    # had to cheange the implementation to switch to precision, from a log10() operation
    assert_equal "$ 5.01", ("$ 139.76".to_commodity * (22290.0 / 622290.0)).round(2).to_s
  end

  def test_floor
    assert_equal '$ 123.45', '$ 123.455'.to_commodity.floor(2).to_s
    assert_equal '$ -123.45', '$ -123.455'.to_commodity.floor(2).to_s
    assert_equal '$ 123.45', '$ 123.459999999999'.to_commodity.floor(2).to_s
    assert_equal '$ 123.454545', '$ 123.4545454545454'.to_commodity.floor(6).to_s
    assert_equal '$ -123.45', '$ -123.459999999999'.to_commodity.floor(2).to_s
    assert_equal '$ 123.45', '$ 123.454444449'.to_commodity.floor(2).to_s
    assert_equal '$ -123.45', '$ -123.454444449'.to_commodity.floor(2).to_s
    assert_equal '$ 123.44', '$ 123.44'.to_commodity.floor(2).to_s
    assert_equal '$ -123.44', '$ -123.44'.to_commodity.floor(2).to_s
    assert_equal '$ 123.4000', '$ 123.4'.to_commodity.floor(4).to_s
    assert_equal '$ -123.4000', '$ -123.4'.to_commodity.floor(4).to_s
    assert_equal '$ 123.0000', '$ 123'.to_commodity.floor(4).to_s
    assert_equal '$ -123.0000', '$ -123'.to_commodity.floor(4).to_s
    assert_equal '$ 123', '$ 123.0455555555'.to_commodity.floor(0).to_s
    assert_equal '$ -123', '$ -123.0455555555'.to_commodity.floor(0).to_s
    assert_equal '$ 999.99', '$ 999.99999'.to_commodity.floor(2).to_s
    assert_equal '$ -999.99', '$ -999.99999'.to_commodity.floor(2).to_s

    assert_equal '$ 123.45', '$ 123.454'.to_commodity.floor(2).to_s
    assert_equal '$ -123.45', '$ -123.454'.to_commodity.floor(2).to_s

    # Found/fixed on 2021-10-25:
    assert_equal '$ 2584.09', '$ 2584.09'.to_commodity.floor(2).to_s
    assert_equal '$ 2584.009', '$ 2584.009'.to_commodity.floor(3).to_s
    assert_equal '$ 2584.009', '$ 2584.009'.to_commodity.floor(3).to_s
    assert_equal '$ 2584.900', '$ 2584.900'.to_commodity.floor(3).to_s
    assert_equal '$ 2584.9', '$ 2584.9'.to_commodity.floor(1).to_s
  end

  def test_to_s_features
    assert_equal '$ 0.00', '$ 0'.to_commodity.to_s(commatize: true)
    assert_equal '$ 1.00', '$ 1.00'.to_commodity.to_s(commatize: true)
    assert_equal '$ 12.00', '$ 12.00'.to_commodity.to_s(commatize: true)
    assert_equal '$ 123.00', '$ 123.00'.to_commodity.to_s(commatize: true)
    assert_equal '$ 1,234.00', '$ 1234.00'.to_commodity.to_s(commatize: true)
    assert_equal '$ 12,345.00', '$ 12345.00'.to_commodity.to_s(commatize: true)
    assert_equal '$ 123,456.00', '$ 123456.00'.to_commodity.to_s(commatize: true)
    assert_equal '$ 1,234,567.00', '$ 1234567.00'.to_commodity.to_s(commatize: true)

    assert_equal '$ 123', '$ 123.00'.to_commodity.to_s(precision: 0)
    assert_equal '$ 123.0', '$ 123.00'.to_commodity.to_s(precision: 1)
    assert_equal '$ 123.00', '$ 123.00'.to_commodity.to_s(precision: 2)
    assert_equal '$ 123.000', '$ 123.00'.to_commodity.to_s(precision: 3)
    assert_equal '$ 123.0000', '$ 123.00'.to_commodity.to_s(precision: 4)
    
    assert_equal '$ 123.46', '$ 123.455'.to_commodity.to_s(precision: 2)
    assert_equal '$ 123.45', '$ 123.454'.to_commodity.to_s(precision: 2)
    assert_equal '$ 124', '$ 123.5'.to_commodity.to_s(precision: 0)
    assert_equal '$ 123', '$ 123.4'.to_commodity.to_s(precision: 0)
    assert_equal '$ 1000', '$ 999.5'.to_commodity.to_s(precision: 0)

    assert_equal '$ 0.00000', '$ 0'.to_commodity.to_s(precision: 5)

    assert_equal '$ 1,234,567.00000', '$ 1234567.00'.to_commodity.to_s(
      commatize: true, precision: 5)
  end

  def test_commodity_from_s_with_double_quotes
    # Seems like we need to support commodities in these forms, after spending
    # some time going through the ledger documentation:

    palette_cleanser = "1 FLORIDAHOME".to_commodity
    assert_equal 1, palette_cleanser.quantity
    assert_equal 'FLORIDAHOME', palette_cleanser.alphabetic_code
    assert_equal 'FLORIDAHOME', palette_cleanser.code
    assert_equal '1 FLORIDAHOME', palette_cleanser.to_s

    crab_apples = '100 "crab apples"'.to_commodity
    assert_equal 100, crab_apples.quantity
    assert_equal 'crab apples', crab_apples.alphabetic_code
    assert_equal 'crab apples', crab_apples.code
    assert_equal '100 "crab apples"', crab_apples.to_s

    reverse_crab_apples = '"crab apples" 100'.to_commodity
    assert_equal 100, reverse_crab_apples.quantity
    assert_equal 'crab apples', reverse_crab_apples.alphabetic_code
    assert_equal 'crab apples', reverse_crab_apples.code
    # NOTE: We're opinionated on this, in our to_s. So, we don't return the
    # original string
    assert_equal '100 "crab apples"', reverse_crab_apples.to_s

    pesky_code = '1 "test \\" ing"'.to_commodity
    assert_equal 1, pesky_code.quantity
    assert_equal 'test \\" ing', pesky_code.alphabetic_code
    assert_equal 'test \\" ing', pesky_code.code
    assert_equal '1 "test \\" ing"', pesky_code.to_s

    reverse_pesky_code = '"test \\" ing" 1'.to_commodity
    assert_equal 1, reverse_pesky_code.quantity
    assert_equal 'test \\" ing', reverse_pesky_code.alphabetic_code
    assert_equal 'test \\" ing', reverse_pesky_code.code
    # NOTE: We're opinionated on this, in our to_s. So, we don't return the
    # original string
    assert_equal '1 "test \\" ing"', reverse_pesky_code.to_s
  end

  # This code path appeared, when parsing the results of "--empty" in register
  # queries. Here's what's in the xml:
  #  <post-amount>
  #    <amount>
  #    <quantity>0</quantity>
  #    </amount>
  #  </post-amount>
  # For some months, when 'nothing' happens, a commodity of type '0'
  # appears. I don't know what the 'best' thing to do is here. But, atm, I think
  # this output suffices....
  def test_commodity_from_string_of_zero
    zero = RRA::Journal::Commodity.from_symbol_and_amount(nil, '0')

    assert_equal 0, zero.quantity
    assert_nil zero.alphabetic_code
    assert_nil zero.code
    assert_equal '0', zero.to_s
  end

  private

  def commodity(str)
    RRA::Journal::Commodity.from_s str
  end

  def commodity_op(lstr, op, rstr)
    commodity(lstr).send(op, commodity(rstr)).to_s
  end
end
