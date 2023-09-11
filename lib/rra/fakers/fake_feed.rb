# frozen_string_literal: true

require_relative 'faker_helpers'
require_relative '../journal/currency'

module RRA
  module Fakers
    # Contains faker implementations that produce CSV files, for use as a data feed
    class FakeFeed < Faker::Base
      class << self
        include FakerHelpers

        # This error is thrown when there is a mismatch between two parameter arrays, passed to
        # a function, whose lengths are required to match.
        class ParameterLengthError < StandardError
          MSG_FORMAT = 'Expected %<expected>s elements in %<parameter>s, but found %<found>s'

          def initialize(parameter, expected, found)
            super format(MSG_FORMAT, expected: expected, parameter: parameter, found: found)
          end
        end

        DEFAULT_LENGTH_IN_DAYS = 365 / 4
        DEFAULT_POST_COUNT = 300
        FEED_COLUMNS = ['Date', 'Type', 'Description', 'Withdrawal (-)', 'Deposit (+)', 'RunningBalance'].freeze
        DEFAULT_CURRENCY = RRA::Journal::Currency.from_code_or_symbol('$')

        # Generates a basic csv feed string, that resembles thos

        # Generates a basic csv feed string, that resembles those offered by banking institutions
        #
        # @param from [Date] The date to start generated feed from
        # @param to [Date] The date to end generated feed
        # @param income_descriptions [Array] Strings containing the pool of available income descriptions, for use in
        #                                    random selection
        # @param expense_descriptions [Array] Strings containing the pool of available expense descriptions, for use in
        #                                     random selection
        # @param deposit_average [RRA::Journal::Commodity] The average deposit amount
        # @param deposit_stddev [Float] The stand deviation, on random deposits
        # @param withdrawal_average [RRA::Journal::Commodity] The average withdrawal amount
        # @param withdrawal_stddev [Float] The stand deviation, on random withdrawals
        # @param starting_balance [RRA::Journal::Commodity]
        #        The balance of the account, before generating the transactions in the feed
        # @param post_count [Numeric] The number of transactions to generate, in this csv feed
        # @param deposit_ratio [Float] The odds ratio, for a given transaction, to be a deposit
        # @param entries [Array] An array of Array's, that are appended to the generated entries (aka 'lines')
        # @return [String] A CSV, containing the generated transactions
        def basic_checking(from: ::Date.today,
                           to: from + DEFAULT_LENGTH_IN_DAYS,
                           expense_descriptions: nil,
                           income_descriptions: nil,
                           deposit_average: RRA::Journal::Commodity.from_symbol_and_amount('$', 6000),
                           deposit_stddev: 500.0,
                           withdrawal_average: RRA::Journal::Commodity.from_symbol_and_amount('$', 300),
                           withdrawal_stddev: 24.0,
                           post_count: DEFAULT_POST_COUNT,
                           starting_balance: RRA::Journal::Commodity.from_symbol_and_amount('$', 5000),
                           deposit_ratio: 0.05,
                           entries: [])

          running_balance = starting_balance.dup

          entry_to_row = lambda do |entry|
            FEED_COLUMNS.map do |column|
              if column == 'RunningBalance'
                deposit = entry['Deposit (+)']
                withdrawal = entry['Withdrawal (-)']

                running_balance = withdrawal.nil? ? running_balance + deposit : running_balance - withdrawal
              else
                entry[column]
              end
            end
          end

          # Newest to oldest:
          to_csv do |csv|
            dates = entries_over_date_range from, to, post_count

            dates.each_with_index do |date, i|
              # If there are any :entries to insert, in this date, do that now:
              entries.each do |entry|
                csv << entry_to_row.call(entry) if entry['Date'] <= date && (i.zero? || entry['Date'] > dates[i - 1])
              end

              accumulator, mean, stddev, type, description = *(
                if Faker::Boolean.boolean true_ratio: deposit_ratio
                  [:+, deposit_average.to_f, deposit_stddev, 'ACH',
                   format('%s DIRECT DEP',
                          income_descriptions ? income_descriptions.sample : Faker::Company.name.upcase)]
                else
                  [:-, withdrawal_average.to_f, withdrawal_stddev, 'VISA',
                   expense_descriptions ? expense_descriptions.sample : Faker::Company.name.upcase]
                end)

              amount = RRA::Journal::Commodity.from_symbol_and_amount(
                DEFAULT_CURRENCY.symbol,
                Faker::Number.normal(mean: mean, standard_deviation: stddev)
              )

              running_balance = running_balance.send accumulator, amount

              amounts = [nil, amount]
              csv << ([date, type, description] + (accumulator == :- ? amounts.reverse : amounts) + [running_balance])
            end

            # Are there any more entries? If so, sort 'em and push them:
            entries.each { |entry| csv << entry_to_row.call(entry) if entry['Date'] > dates.last }
          end
        end

        # Generates a basic csv feed string, that resembles those offered by banking institutions. Unlike
        # #basic_checking, this faker supports a set of parameters that will better conform the output to a
        # typical model of commerence for an employee with a paycheck and living expenses. As such, the
        # parameters are a bit different, and suited to plotting aesthetics.
        #
        # @param from [Date] The date to start generated feed from
        # @param to [Date] The date to end generated feed
        # @param income_sources [Array] Strings containing the pool of income companies, to use for growing our assets
        # @param expense_sources [Array] Strings containing the pool of available expense companies, to use for
        #                                shrinking our assets
        # @param opening_liability_balance [RRA::Journal::Commodity] The opening balance of the liability account,
        #                                                            preceeding month zero
        # @param opening_asset_balance [RRA::Journal::Commodity] The opening balance of the asset account, preceeding
        #                                                        month zero
        # @param liability_sources [Array] Strings containing the pool of available liability sources (aka 'companies')
        # @param liabilities_by_month [Array] An array of RRA::Journal::Commodity entries, indicatiing the liability
        #                                     balance for a month with offset n, from the from date
        # @param assets_by_month [Array] An array of RRA::Journal::Commodity entries, indicating the asset
        #                                balance for a month with offset n, from the from date
        # @return [String] A CSV, containing the generated transactions
        def personal_checking(from: ::Date.today,
                              to: from + DEFAULT_LENGTH_IN_DAYS,
                              expense_sources: [Faker::Company.name.tr('^a-zA-Z0-9 ', '')],
                              income_sources: [Faker::Company.name.tr('^a-zA-Z0-9 ', '')],
                              monthly_expenses: {},
                              opening_liability_balance: '$ 0.00'.to_commodity,
                              opening_asset_balance: '$ 0.00'.to_commodity,
                              liability_sources: [Faker::Company.name.tr('^a-zA-Z0-9 ', '')],
                              liabilities_by_month: months_in_range(from, to).map.with_index do |_, n|
                                RRA::Journal::Commodity.from_symbol_and_amount('$', 200 + ((n + 1) * 800))
                              end,
                              assets_by_month: months_in_range(from, to).map.with_index do |_, n|
                                RRA::Journal::Commodity.from_symbol_and_amount('$', 500 * ((n + 1) * 5))
                              end)

          num_months_in_range = ((to.year * 12) + to.month) - ((from.year * 12) + from.month) + 1

          ['liabilities_by_month', liabilities_by_month.length,
           'assets_by_month', assets_by_month.length].each_slice(2) do |attr, length|
            raise ParameterLengthError.new(attr, num_months_in_range, length) unless num_months_in_range == length
          end

          monthly_expenses.each_pair do |company, expenses_by_month|
            unless num_months_in_range == expenses_by_month.length
              attr = format('monthly_expenses: %s', company)
              raise ParameterLengthError.new(attr, num_months_in_range, expenses_by_month.length)
            end
          end

          liability_balance = opening_liability_balance
          asset_balance = opening_asset_balance

          # Newest to oldest:
          to_csv do |csv|
            months_in_range(from, to).each_with_index do |first_of_month, i|
              expected_liability = liabilities_by_month[i]

              # Let's adjust the liability to suit
              csv << if expected_liability > liability_balance
                       # We need to borrow some more money:
                       deposit = (expected_liability - liability_balance).abs
                       asset_balance += deposit
                       liability_balance += deposit
                       [first_of_month, 'ACH', liability_sources.sample, nil, deposit, asset_balance]
                     elsif expected_liability < liability_balance
                       # We want to pay off our balance:
                       payment = (expected_liability - liability_balance).abs
                       asset_balance -= payment
                       liability_balance -= payment
                       [first_of_month, 'ACH', liability_sources.sample, payment, nil, asset_balance]
                     end

              expected_assets = assets_by_month[i]

              monthly_expenses.each_pair do |company, expenses_by_month|
                asset_balance -= expenses_by_month[i]
                csv << [first_of_month, 'VISA', company, expenses_by_month[i], nil, asset_balance]
              end

              # Let's adjust the assets to suit
              if expected_assets > asset_balance
                # We need a paycheck:

                deposit = expected_assets - asset_balance
                asset_balance += deposit
                csv << [first_of_month, 'ACH', income_sources.sample, nil, deposit, asset_balance]
              elsif expected_assets < asset_balance
                # We need to generate some expenses:
                payment = asset_balance - expected_assets
                asset_balance -= payment
                csv << [first_of_month, 'VISA', expense_sources.sample, payment, nil, asset_balance]
              end
            end
          end
        end

        private

        def months_in_range(from, to)
          ret = []
          i = 0
          loop do
            ret << (Date.new(from.year, from.month, 1) >> i)
            i += 1
            break if ret.last.year == to.year && ret.last.month == to.month
          end

          ret
        end

        def to_csv(&block)
          converter = lambda do |field|
            case field
            when Date
              field.strftime('%m/%d/%Y')
            when RRA::Journal::Commodity
              field.to_s(precision: DEFAULT_CURRENCY.minor_unit)
            else
              field
            end
          end

          CSV.generate force_quotes: true, headers: FEED_COLUMNS, write_headers: true, write_converters: [converter],
                       &block
        end
      end
    end
  end
end
