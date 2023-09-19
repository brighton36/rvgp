# frozen_string_literal: true

module Validations
  # This class implements a journal validation that ensures there are no uncategorized
  # expenses in the journal
  class UncategorizedValidation < RRA::JournalValidationBase
    def validate
      validate_no_balance 'Uncategorized Transactions', 'Unknown'
    end
  end
end
