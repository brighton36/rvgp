#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'

require_relative '../lib/rvgp'
require_relative '../lib/rvgp/fakers/fake_reconciler'

# Minitest class, used to test RRA::Fakers::FakeReconciler
class TestFakeReconciler < Minitest::Test
  def test_basic_reconciler_with_format_path
    reconciler = Psych.load RRA::Fakers::FakeReconciler.basic_checking(
      label: 'Personal AcmeBank:Checking (2020)',
      input_path: '2020-personal-basic-checking.csv',
      output_path: '2020-personal-basic-checking.journal',
      format_path: 'config/csv-format-acme-checking.yml',
      income: incomes,
      expense: expenses
    )

    assert_equal 'Personal:Assets:AcmeBank:Checking', reconciler['from']
    assert_equal 'Personal AcmeBank:Checking (2020)', reconciler['label']
    assert_equal 'config/csv-format-acme-checking.yml', reconciler['format'].path
    assert_equal '2020-personal-basic-checking.csv', reconciler['input']
    assert_equal '2020-personal-basic-checking.journal', reconciler['output']
    assert_nil reconciler['balances']

    assert_equal incomes + [{ 'match' => '/.*/', 'to' => 'Personal:Income:Unknown' }], reconciler['income']
    assert_equal expenses + [{ 'match' => '/.*/', 'to' => 'Personal:Expenses:Unknown' }], reconciler['expense']
  end

  def test_basic_reconciler_without_format
    reconciler = Psych.load RRA::Fakers::FakeReconciler.basic_checking(
      label: 'Personal AcmeBank:Checking (2020)',
      input_path: '2020-personal-basic-checking.csv',
      output_path: '2020-personal-basic-checking.journal',
      income: incomes,
      expense: expenses
    )

    assert_equal true, reconciler['format']['csv_headers']
    assert_equal true, reconciler['format']['reverse_order']
    assert_equal '$', reconciler['format']['default_currency']
    assert_equal %w[date amount description], reconciler['format']['fields'].keys
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
