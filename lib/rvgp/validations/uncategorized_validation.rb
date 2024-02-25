# frozen_string_literal: true

module RRA
  # This module provides a number of basic, and common, validations for use in your projects
  module Validations
    # This class implements a journal validation that ensures there are no uncategorized
    # expenses in the journal
    class UncategorizedValidation < RRA::Base::JournalValidation
      # Ensures that there is no balance for 'Unknown' categories in a journal
      def validate
        validate_no_balance 'Uncategorized Transactions', 'Unknown'
      end
    end
  end
end
