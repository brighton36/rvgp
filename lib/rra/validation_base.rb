# frozen_string_literal: true

require_relative 'descendant_registry'

module RRA
  # This module offers mixin functions, for use with your validations.
  module ValidationBaseHelpers
    NAME_CAPTURE = /\A(.+)Validation\Z/.freeze

    def valid?
      @errors = []
      @warnings = []
      validate
      (@errors.length + @warnings.length).zero?
    end

    def self.included(base)
      base.instance_eval do
        attr_reader :errors, :warnings
      end
    end

    private

    def format_error_or_warning(msg, citations = nil)
      [msg, citations || []]
    end

    def error!(*args)
      @errors << format_error_or_warning(*args)
    end

    def warning!(*args)
      @warnings << format_error_or_warning(*args)
    end
  end

  # This base class is intended for use by inheritors, and contains most of the
  # logic needed, to implement the validation of a journal file
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
                                     { file: transformer.output_file, sort: 'date' }.merge(ledger_opts)

      error_citations = results.transactions.map do |posting|
        format '%<date>s: %<payee>s', date: posting.date.to_s, payee: posting.payee
      end

      error! with_error_msg, error_citations unless error_citations.empty?
    end

    def validate_no_balance(with_error_msg, account)
      results = RRA::HLedger.balance account, file: transformer.output_file

      error_citations = results.accounts.map do |ra|
        ra.amounts.map { |commodity| [ra.fullname, RRA.pastel.red('━'), commodity.to_s].join(' ') }
      end

      error_citations.flatten!

      error! with_error_msg, error_citations unless error_citations.empty?
    end
  end

  # This base class is intended for use by inheritors, and contains most of the
  # logic needed, to implement the validation of a system file
  class SystemValidationBase
    include ValidationBaseHelpers
    include RRA::DescendantRegistry

    task_names = ->(registry) { registry.names.map { |name| format('validate_system:%s', name) } }
    register_descendants RRA, :system_validations,
                         name_capture: NAME_CAPTURE,
                         accessors: { task_names: task_names }

    def mark_validated!
      FileUtils.touch self.class.build_validation_file_path
    end

    def self.validated?
      FileUtils.uptodate? build_validation_file_path, [
        RRA.app.config.build_path('journals/*.journal'),
        RRA.app.config.project_path('journals/*.journal')
      ].map { |glob| Dir.glob glob }.flatten
    end

    def self.status_label
      const_get :STATUS_LABEL
    end

    def self.description
      const_get :DESCRIPTION
    end

    def self.build_validation_file_path
      RRA.app.config.build_path(format('journals/system-validation-%s.valid', name.to_s))
    end
  end
end
