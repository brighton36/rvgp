class UncategorizedValidation < RRA::JournalValidationBase
  def validate
    validate_no_balance "Uncategorized Transacations", 'Unknown'
  end
end
