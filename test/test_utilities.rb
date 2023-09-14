#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'

require_relative '../lib/rra'
require_relative '../lib/rra/utilities'

# RRA::Utilities tests
class TestUtilities < Minitest::Test
  include RRA::Utilities

  # This is kind of a weird function... just sayin...
  def test_months_through_dates
    string_to_date = ->(s) { Date.strptime s }

    assert_equal %w[2019-01-01 2019-02-01 2019-03-01 2019-04-01 2019-05-01 2019-06-01
                    2019-07-01 2019-08-01 2019-09-01 2019-10-01 2019-11-01 2019-12-01].collect(&string_to_date),
                 months_through_dates(
                   *%w[2019-01-01 2019-02-01 2019-03-01 2019-04-01 2019-05-01 2019-06-01
                       2019-07-01 2019-08-01 2019-09-01 2019-10-01 2019-11-01 2019-12-01
                       2019-01-01 2019-02-01 2019-03-01 2019-04-01 2019-05-01 2019-06-01
                       2019-07-01 2019-08-01 2019-09-01 2019-10-01 2019-11-01 2019-12-01].collect(&string_to_date)
                 )

    assert_equal %w[2021-01-01 2021-02-01 2021-03-01 2021-04-01 2021-05-01
                    2021-06-01 2021-07-01 2021-08-01 2021-09-01 2021-10-01
                    2021-11-01].collect(&string_to_date),
                 months_through_dates(Date.new(2021, 1, 1), Date.new(2021, 11, 29))

    assert_equal %w[2021-01-01 2021-02-01 2021-03-01 2021-04-01 2021-05-01
                    2021-06-01 2021-07-01 2021-08-01 2021-09-01 2021-10-01
                    2021-11-01 2021-12-01 2022-01-01].collect(&string_to_date),
                 months_through_dates(Date.new(2021, 1, 1), Date.new(2022, 1, 1))

    assert_equal %w[2018-01-01 2018-02-01 2018-03-01 2018-04-01 2018-05-01
                    2018-06-01 2018-07-01 2018-08-01 2018-09-01 2018-10-01
                    2018-11-01 2018-12-01].collect(&string_to_date),
                 months_through_dates(Date.new(2018, 1, 1), Date.new(2018, 12, 31))

    # I think this is the behavior we want....
    assert_equal %w[2021-01-01 2021-02-01].collect(&string_to_date),
                 months_through_dates(Date.new(2021, 1, 10), Date.new(2021, 2, 10))
  end
end
