#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'

require_relative '../lib/rra'
require_relative '../lib/rra/fakers/fake_feed'
require_relative '../lib/rra/fakers/fake_transformer'

# Minitest class, used to test RRA::Fakers::FakeJournal
class TestFakeFeed < Minitest::Test
  def test_basic_feed
    feed = RRA::Fakers::FakeFeed.basic_checking from: Date.new(2020, 1, 1),
                                                to: Date.new(2020, 3, 31),
                                                post_count: 300

    assert_kind_of String, feed

    csv = CSV.parse feed, headers: true
    assert_equal 300, csv.length

    assert_equal ['Date', 'Type', 'Description', 'Withdrawal (-)', 'Deposit (+)',
                  'RunningBalance'], csv.headers
    assert_equal '01/01/2020', csv.first['Date']
    assert_equal '03/31/2020', csv[-1]['Date']

    csv.each do |row|
      assert_kind_of String, row['Date']
      assert_kind_of String, row['Type']
      assert_kind_of String, row['Description']
      assert_kind_of String, row['Withdrawal (-)']
      assert_kind_of String, row['Deposit (+)']
      assert_kind_of String, row['RunningBalance']

      assert_match(%r{\A\d{2}/\d{2}/\d{4}\Z}, row['Date'])
      assert !row['Type'].empty?
      assert !row['Description'].empty?
      assert_match(/\$ \d+\.\d{2}/,
                   row['Withdrawal (-)'].empty? ? row['Deposit (+)'] : row['Withdrawal (-)'])
      assert_match(/\$ -?\d+\.\d{2}/, row['RunningBalance'])
    end
  end

  def test_descriptions_param
    expense_descriptions = %w[Walmart Amazon Apple CVS Exxon Berkshire Google Microsoft Costco]
    income_descriptions = %w[Uber Cyberdyne]
    feed = RRA::Fakers::FakeFeed.basic_checking post_count: 50,
                                                expense_descriptions: expense_descriptions,
                                                income_descriptions: income_descriptions

    csv = CSV.parse feed, headers: true
    assert_equal 50, csv.length
    csv.each do |row|
      if row['Withdrawal (-)'].empty?
        assert(/\A(.+) DIRECT DEP\Z/.match(row['Description']))
        assert_includes income_descriptions, ::Regexp.last_match(1)
      else
        assert_includes expense_descriptions, row['Description']
      end
    end
  end

  def test_entries_param
    # There isn't an easy way to sort this, atm... so, we just test that these lines are appended
    additional_entries = [
      { 'Date' => Date.new(2019, 12, 31),
        'Type' => 'VISA',
        'Description' => 'Posting from Dec 2019',
        'Withdrawal (-)' => '$ 9.00'.to_commodity },
      { 'Date' => Date.new(2020, 1, 31),
        'Type' => 'VISA',
        'Description' => 'Posting from Jan 2020',
        'Withdrawal (-)' => '$ 12.00'.to_commodity },
      { 'Date' => Date.new(2020, 4, 1),
        'Type' => 'ACH',
        'Description' => 'Posting from Apr 2020',
        'Deposit (+)' => '$ 8.00'.to_commodity }
    ]

    starting_balance = '$ 10000.00'.to_commodity

    feed = RRA::Fakers::FakeFeed.basic_checking from: Date.new(2020, 1, 1),
                                                to: Date.new(2020, 3, 31),
                                                post_count: 300,
                                                starting_balance: starting_balance,
                                                entries: additional_entries
    csv = CSV.parse feed, headers: true

    # First:
    assert_equal csv[0].to_h.values,
                 ['12/31/2019', 'VISA', 'Posting from Dec 2019', '$ 9.00', '',
                  (starting_balance - '$ 9.00'.to_commodity).to_s]

    # Middle (This just happened to consistently be element 100)
    assert_equal csv[100].to_h.values,
                 ['01/31/2020', 'VISA', 'Posting from Jan 2020', '$ 12.00', '',
                  (csv[99]['RunningBalance'].to_commodity - '$ 12.00'.to_commodity).to_s]

    # Last:
    assert_equal csv[-1].to_h.values,
                 ['04/01/2020', 'ACH', 'Posting from Apr 2020', '', '$ 8.00',
                  (csv[-2]['RunningBalance'].to_commodity + '$ 8.00'.to_commodity).to_s]
  end

  def test_personal_checking_feed
    duration_in_months = 12
    from = Date.new 2020, 1, 1
    expense_sources = [Faker::Company.name.tr('^a-zA-Z0-9 ', '')]
    income_sources = [Faker::Company.name.tr('^a-zA-Z0-9 ', '')]
    liability_sources = [Faker::Company.name.tr('^a-zA-Z0-9 ', '')]
    liabilities, assets = 2.times.map do |_|
      duration_in_months.times.map do
        RRA::Journal::Commodity.from_symbol_and_amount '$', Faker::Number.between(from: 0, to: 2_000_000)
      end
    end

    categories = ['Personal:Expenses:Rent', 'Personal:Expenses:Food:Restaurants',
                  'Personal:Expenses:Food:Groceries', 'Personal:Expenses:Drug Stores']

    category_to_company = (categories.map { |category| [category, Faker::Company.name] }).to_h

    monthly_expenses = (category_to_company.keys.map do |category|
      [category_to_company[category],
       12.times.map do |_|
         RRA::Journal::Commodity.from_symbol_and_amount '$', Faker::Number.between(from: 10, to: 1000)
       end]
    end).to_h

    # This one, we'll just try something different with:
    monthly_expenses[category_to_company['Personal:Expenses:Rent']] = ['$ 1500.00'.to_commodity] * 12

    feed = RRA::Fakers::FakeFeed.personal_checking from: from,
                                                   to: from >> (duration_in_months - 1),
                                                   expense_sources: expense_sources,
                                                   income_sources: income_sources,
                                                   monthly_expenses: monthly_expenses,
                                                   liability_sources: liability_sources,
                                                   liabilities_by_month: liabilities,
                                                   assets_by_month: assets

    # Ensure the running balance is making sense:
    running_balance = nil
    CSV.parse(feed, headers: true).each_with_index do |row, i|
      if i.zero?
        running_balance = row['RunningBalance'].to_commodity
        next
      end

      running_balance -= row['Withdrawal (-)'].to_commodity unless row['Withdrawal (-)'].empty?
      running_balance += row['Deposit (+)'].to_commodity unless row['Deposit (+)'].empty?

      assert_equal running_balance.to_s, row['RunningBalance']
    end

    # Now let's ensure the Monthly balances:
    liabilities_match, incomes_match, expenses_match = *[
      'Personal:Liabilities', liability_sources,
      'Personal:Income', income_sources,
      'Personal:Expenses', expense_sources
    ].each_slice(2).map do |category, sources|
      sources.map do |name|
        { match: format('/%s/', name), to: format([category, ':%s'].join, name.tr(' ', '')) }
      end
    end

    monthly_expenses_match = category_to_company.each_with_object([]) do |pair, sum|
      sum << { match: format('/%s/', pair.last), to: pair.first }
    end

    journal = reconcile_journal feed,
                                income: incomes_match + liabilities_match,
                                expense: expenses_match + liabilities_match + monthly_expenses_match

    # This was kinda copy pasta'd from the ReportBase
    result_assets, result_liabilities = %w[Assets Liabilities].collect { |acct| account_by_month acct, journal }

    assert_equal duration_in_months, result_liabilities.length
    assert_equal liabilities, result_liabilities.map(&:invert!)
    assert_equal duration_in_months, result_assets.length
    assert_equal assets, result_assets

    # Run the monthly for each of the monthly_expenses
    categories.each do |category|
      category_by_month = account_by_month category, journal, :amount_in

      assert_equal duration_in_months, category_by_month.length
      assert_equal monthly_expenses[category_to_company[category]], category_by_month
    end

    assert_equal [], account_by_month('Unknown', journal)
  end

  private

  def account_by_month(acct, journal_s, accrue_by = :total_in)
    ledger = RRA::Ledger.new
    ledger.register(acct, monthly: true, from_s: journal_s)
          .transactions.map do |tx|
            assert_equal 1, tx.postings.length
            tx.postings[0].send(accrue_by, '$')
          end
  end

  def reconcile_journal(feed, transformer_opts)
    journal_file = Tempfile.open %w[rra_test .journal]

    feed_file = Tempfile.open %w[rra_test .csv]
    feed_file.write feed
    feed_file.close

    yaml_file = Tempfile.open %w[rra_test .yaml]

    yaml_file.write RRA::Fakers::FakeTransformer.basic_checking(
      **{ label: 'Personal AcmeBank:Checking',
          input_path: feed_file.path,
          output_path: journal_file.path }.merge(transformer_opts)
    )

    yaml_file.close

    RRA::Transformers::CsvTransformer.new(RRA::Yaml.new(yaml_file.path)).to_ledger
  ensure
    [feed_file, yaml_file, journal_file].each do |f|
      f.close
      f.unlink
    end
  end
end
