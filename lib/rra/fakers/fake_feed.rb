# frozen_string_literal: true

require_relative 'faker_helpers'

module RRA
  module Fakers
    # Contains faker implementations that produce CSV files, for use as a data feed
    class FakeFeed < Faker::Base
      class << self
        include FakerHelpers

        # Generates a basic csv feed string, that resembles those offered by banking institutions
        #
        # @param from [Date] The date to start generated feed from
        # @param to [Date] The date to end generated feed
        # @param income_descriptions [Array] Strings containing the pool of available income descriptions, for use in random selection
        # @param expense_descriptions [Array] Strings containing the pool of available expense descriptions, for use in random selection
        # @param deposit_average [RRA::Journal::Commodity] The average deposit amount
        # @param deposit_stddev [Float] The stand deviation, on random deposits
        # @param withdrawal_average [RRA::Journal::Commodity] The average withdrawal amount
        # @param withdrawal_stddev [Float] The stand deviation, on random withdrawals
        # @param starting_balance [RRA::Journal::Commodity]
        #        The balance of the account, before generating the transactions in the feed
        # @param post_count [Numeric] The number of transactions to generate, in this csv feed
        # @param deposit_ratio [Float] The odds ratio, for a given transaction, to be a deposit
        # @return [String] A CSV, containing the generated transactions
        def basic_checking(from: ::Date.today,
                           to: from + (365 / 4),
                           expense_descriptions: nil,
                           income_descriptions: nil,
                           deposit_average: '$ 2000.00'.to_commodity,
                           deposit_stddev: 500.0,
                           withdrawal_average: '$ 100.00'.to_commodity,
                           withdrawal_stddev: 24.0,
                           post_count: 300,
                           starting_balance: '$ 5000.00'.to_commodity,
                           deposit_ratio: 0.05)

          currency = RRA::Journal::Currency.from_code_or_symbol(starting_balance.code)
          running_balance = starting_balance.dup

          CSV.generate headers: :first_row, force_quotes: true do |csv|
            csv << ['Date', 'Type', 'Description', 'Withdrawal (-)', 'Deposit (+)', 'RunningBalance']

            entries_over_date_range(post_count, from, to).each do |date|
              is_deposit = Faker::Boolean.boolean true_ratio: deposit_ratio

              if is_deposit
                accumulate_by = :+
                amount_args = { mean: deposit_average.to_f, standard_deviation: deposit_stddev }
                type = 'ACH'
                description = format '%s DIRECT DEP',
                                     income_descriptions ? income_descriptions.sample : Faker::Company.name.upcase
              else
                accumulate_by = :-
                amount_args = { mean: withdrawal_average.to_f, standard_deviation: withdrawal_stddev }
                type = 'VISA'
                description = expense_descriptions ? expense_descriptions.sample : Faker::Company.name.upcase
              end

              amount = RRA::Journal::Commodity.from_symbol_and_amount(currency.symbol,
                                                                      Faker::Number.normal(**amount_args))
              amounts = [nil, amount.to_s(precision: currency.minor_unit)]
              amounts.reverse! if accumulate_by == :-
              running_balance = running_balance.send accumulate_by, amount

              csv << [
                [date.strftime('%m/%d/%Y'), type, description],
                amounts,
                [running_balance.to_s(precision: currency.minor_unit)]
              ].sum([])
            end
          end
        end
      end
    end
  end
end
