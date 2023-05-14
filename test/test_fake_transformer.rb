#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'

require_relative '../lib/rra'
require_relative '../lib/rra/fakers/fake_transformer'

# Minitest class, used to test RRA::Fakers::FakeTransformer
class TestFakeTransformer < Minitest::Test
  def test_basic_transformer
    incomes = [
      { 'match' => '/MC DONALDS INC DIRECT DEP/', 'to' => 'Personal:Income:McDonalds' },
      { 'match' => '/Airbnb Payments/', 'to' => 'Personal:Income:AirBNB' }
    ]
    expenses = [
      { 'match' => '/(?:Burger King|KFC|Taco Bell)/', 'to' => 'Personal:Expenses:Food:Restaurants' },
      { 'match' => '/(?:Publix|Kroger|Trader Joe)/', 'to' => 'Personal:Expenses:Food:Groceries' },
      { 'match' => '/CHECK (?:100|105|110)/', 'to' => 'Personal:Expenses:Rent' },
      { 'match' => '/T[-]?Mobile/i', 'to' => 'Personal:Expenses:Phone' }
    ]

    transformer = Psych.load RRA::Fakers::FakeTransformer.basic_checking(
      label: 'Personal AcmeBank:Checking (2020)',
      input_path: '2020-personal-basic-checking.csv',
      output_path: '2020-personal-basic-checking.journal',
      income: incomes,
      expense: expenses
    )

    assert_equal 'Personal:Assets:AcmeBank:Checking', transformer['from']
    assert_equal 'Personal AcmeBank:Checking (2020)', transformer['label']
    assert_equal 'config/csv-format-acme-checking.yml', transformer['format'].path
    assert_equal '2020-personal-basic-checking.csv', transformer['input']
    assert_equal '2020-personal-basic-checking.journal', transformer['output']
    assert_nil transformer['balances']

    incomes << { 'match' => '/.*/', 'to' => 'Personal:Income:Unknown' }
    transformer['income'].each_with_index { |income, i| assert_equal incomes[i], income }

    expenses << { 'match' => '/.*/', 'to' => 'Personal:Expenses:Unknown' }
    transformer['expense'].each_with_index { |expense, i| assert_equal expenses[i], expense }
  end
end
