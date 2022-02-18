require_relative 'descendant_registry'

module RRA
  module ValidationBaseHelpers
    NAME_CAPTURE = /\A(.+)Validation\Z/

    def is_valid?
      @errors, @warnings = [], []
      validate
      (@errors.length + @warnings.length) == 0
    end

    private

    def format_error_or_warning(msg, citations = nil)
      [msg, ((citations) ? citations : [])]
    end

    def error!(*args)
      @errors << format_error_or_warning(*args)
    end

    def warning!(*args)
      @warnings << format_error_or_warning(*args)
    end

    def self.included(base)
      base.instance_eval do
        attr_reader :errors, :warnings
      end
    end
  end

  class JournalValidationBase
    include ValidationBaseHelpers
    include RRA::DescendantRegistry

    register_descendants RRA, :journal_validations, name_capture: NAME_CAPTURE

    attr_reader :transformer

    def initialize(transformer)
      @transformer = transformer
    end

    # I suppose we'd want/need an hledger_opts parameter over time...
    def validate_no_transactions(with_error_msg, ledger_opts)
      results = RRA::Ledger.register transformer.from, 
        {file: transformer.output_file, sort: 'date'}.merge(ledger_opts)

      error! with_error_msg, results.transactions.collect{ |posting| 
        '%s: %s' % [ posting.date.to_s, posting.payee ]
        } if results.transactions.length > 0
    end

    def validate_no_balance(with_error_msg, account)
      results = RRA::Ledger.balance account, file: transformer.output_file

      error! with_error_msg, results.accounts.collect{|account| 
        account.amounts.collect{|commodity| 
          [account.fullname, RRA.pastel.red('━'), commodity.to_s].join(' ') }
      }.flatten if results.accounts.length > 0
    end
  end

  class SystemValidationBase
    include ValidationBaseHelpers
    include RRA::DescendantRegistry

    register_descendants RRA, :system_validations, name_capture: NAME_CAPTURE,
      accessors: { task_names: lambda{|registry| 
        registry.names.collect{|name| 'validate_system:%s' % name} } }

    def mark_validated!
      FileUtils.touch self.class.build_validation_file_path
    end

    def self.validated?
      FileUtils.uptodate? build_validation_file_path, [
        RRA.app.config.build_path('journals/*.journal'), 
        RRA.app.config.project_path('journals/*.journal')
      ].collect{|glob| Dir.glob glob}.flatten
    end

    def self.status_label
      self.const_get :STATUS_LABEL
    end
    
    def self.description
      self.const_get :DESCRIPTION
    end

    private

    def self.build_validation_file_path
      RRA.app.config.build_path('journals/system-validation-%s.valid' % [
        self.name.to_s])
    end

  end
end
