class UncategorizedValidation < RRA::JournalValidationBase
  def validate
    validate_no_balance "Uncategorized Transactions", 'Unknown'
  end
end
