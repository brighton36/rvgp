# frozen_string_literal: true

require 'faker'

require_relative 'journal'
require_relative 'journal/commodity'

module Faker
  # Contains faker implementations that produce pta journals
  class FakeJournal < Faker::Base
    class << self
      # Generates a basic journal, that credits/debits from a Cash account
      #
      # @param from [Date] The date to start generated postings from
      # @param to [Date] The date to end generated postings
      # @param sum [RRA::Journal::Commodity]
      #        The amount that all postings in the generated journal, will add up to
      # @param post_count [Numeric] The number of postings to generate, in this journal
      # @return [RRA::Journal] A fake journal, conforming to the provided params
      def basic_cash(from: ::Date.today, to: from + 9, sum: '$ 100.00'.to_commodity, post_count: 10)
        RRA::Journal.new(
          map_uniformly_distributed_amounts(from, to, sum, post_count) do |date, amount, _|
            simple_posting date, amount
          end
        )
      end

      private

      def map_uniformly_distributed_amounts(from, to, sum, count, &block)
        raise StandardError unless [from.is_a?(::Date),
                                    to.is_a?(::Date),
                                    sum.is_a?(RRA::Journal::Commodity),
                                    count.is_a?(Numeric)].all?

        day_increment = (((to - from).to_f.abs + 1) / (count - 1)).floor

        # If we have more postings than days, I guess, raise Unsupported
        raise StandardError if day_increment <= 0

        amount_increment = (sum / count).floor sum.precision
        running_sum = nil

        1.upto(count).map do |n|
          post_amount = n == count ? (sum - running_sum) : amount_increment
          post_date = n == count ? to : from + (day_increment * (n - 1))

          running_sum = running_sum.nil? ? post_amount : (running_sum + post_amount)

          block.call post_date, post_amount, running_sum
        end
      end

      def simple_posting(date, amount)
        transfers = [to_transfer('Expense', commodity: amount), to_transfer('Cash')]
        RRA::Journal::Posting.new date, Faker::Company.name, transfers: transfers
      end

      def to_transfer(*args)
        RRA::Journal::Posting::Transfer.new(*args)
      end
    end
  end
end
