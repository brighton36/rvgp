# frozen_string_literal: true

require 'faker'

require_relative '../journal'
require_relative '../journal/commodity'

module RRA
  module Fakers
    # This module offers code that is shared by a number of our fakers. Mostly,
    # this just keeps those fakers DRY.
    module FakerHelpers
      private

      # Uniformly distribute the transactions over a date range
      def entries_over_date_range(from, to, count = nil)
        raise StandardError unless [from.is_a?(::Date), to.is_a?(::Date), count.is_a?(Numeric)].all?

        run_length = ((to - from).to_f + 1) / (count - 1)

        1.upto(count).map { |n| n == count ? to : from + (run_length * (n - 1)) }
      end
    end
  end
end
