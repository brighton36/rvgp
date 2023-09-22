# frozen_string_literal: true

module RRA
  module Validations
    # This class implements a journal validation that ensures there are no uncategorized
    # expenses in the journal
    class UncategorizedValidation < RRA::Base::JournalValidation
      def validate
        validate_no_balance 'Uncategorized Transactions', 'Unknown'
      end
    end
  end
end
