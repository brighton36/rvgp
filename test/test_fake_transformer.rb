#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'

require_relative '../lib/rra'
require_relative '../lib/rra/fakers/fake_transformer'

# Minitest class, used to test RRA::Fakers::FakeTransformer
class TestFakeTransformer < Minitest::Test
  def test_basic_transformer_with_format_path
    transformer = Psych.load RRA::Fakers::FakeTransformer.basic_checking(
      label: 'Personal AcmeBank:Checking (2020)',
      input_path: '2020-personal-basic-checking.csv',
      output_path: '2020-personal-basic-checking.journal',
      format_path: 'config/csv-format-acme-checking.yml',
      income: incomes,
      expense: expenses
    )

    assert_equal 'Personal:Assets:AcmeBank:Checking', transformer['from']
    assert_equal 'Personal AcmeBank:Checking (2020)', transformer['label']
    assert_equal 'config/csv-format-acme-checking.yml', transformer['format'].path
    assert_equal '2020-personal-basic-checking.csv', transformer['input']
    assert_equal '2020-personal-basic-checking.journal', transformer['output']
    assert_nil transformer['balances']

    assert_equal incomes + [{ 'match' => '/.*/', 'to' => 'Personal:Income:Unknown' }], transformer['income']
    assert_equal expenses + [{ 'match' => '/.*/', 'to' => 'Personal:Expenses:Unknown' }], transformer['expense']
  end

  def test_basic_transformer_without_format
    transformer = Psych.load RRA::Fakers::FakeTransformer.basic_checking(
      label: 'Personal AcmeBank:Checking (2020)',
      input_path: '2020-personal-basic-checking.csv',
      output_path: '2020-personal-basic-checking.journal',
      income: incomes,
      expense: expenses
    )

    assert_equal true, transformer['format']['csv_headers']
    assert_equal true, transformer['format']['reverse_order']
    assert_equal '$', transformer['format']['default_currency']
    assert_equal %w[date amount description], transformer['format']['fields'].keys
  end

  private

  def incomes
    [{ 'match' => '/MC DONALDS INC DIRECT DEP/', 'to' => 'Personal:Income:McDonalds' },
     { 'match' => '/Airbnb Payments/', 'to' => 'Personal:Income:AirBNB' }]
  end

  def expenses
    [{ 'match' => '/(?:Burger King|KFC|Taco Bell)/', 'to' => 'Personal:Expenses:Food:Restaurants' },
     { 'match' => '/(?:Publix|Kroger|Trader Joe)/', 'to' => 'Personal:Expenses:Food:Groceries' },
     { 'match' => '/CHECK (?:100|105|110)/', 'to' => 'Personal:Expenses:Rent' },
     { 'match' => '/T[-]?Mobile/i', 'to' => 'Personal:Expenses:Phone' }]
  end
end
