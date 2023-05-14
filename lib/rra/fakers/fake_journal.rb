# frozen_string_literal: true

require_relative 'faker_helpers'

module RRA
  module Fakers
    # Contains faker implementations that produce pta journals
    class FakeJournal < Faker::Base
      class << self
        include FakerHelpers

        # Generates a basic journal, that credits/debits from a Cash account
        #
        # @param from [Date] The date to start generated postings from
        # @param to [Date] The date to end generated postings
        # @param sum [RRA::Journal::Commodity]
        #        The amount that all postings in the generated journal, will add up to
        # @param post_count [Numeric] The number of postings to generate, in this journal
        # @return [RRA::Journal] A fake journal, conforming to the provided params
        def basic_cash(from: ::Date.today, to: from + 9, sum: '$ 100.00'.to_commodity, post_count: 10)
          raise StandardError unless sum.is_a?(RRA::Journal::Commodity)

          amount_increment = (sum / post_count).floor sum.precision
          running_sum = nil

          RRA::Journal.new(entries_over_date_range(post_count, from, to).map.with_index do |date, i|
            post_amount = i + 1 == post_count ? (sum - running_sum) : amount_increment

            running_sum = running_sum.nil? ? post_amount : (running_sum + post_amount)

            simple_posting date, post_amount
          end)
        end

        private

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
end