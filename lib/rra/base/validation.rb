# frozen_string_literal: true

require_relative '../descendant_registry'

module RRA
  module Base
    # The base class, from which all Journal and System validations inherit. This
    # class contains the code shared by all validations.
    class Validation
      include RRA::PtaAdapter::AvailabilityHelper

      NAME_CAPTURE = /([^:]+)Validation\Z/.freeze

      attr_reader :errors, :warnings

      def initialize(*_args)
        @errors = []
        @warnings = []
      end

      def valid?
        @errors = []
        @warnings = []
        validate
        (@errors.length + @warnings.length).zero?
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
    class JournalValidation < Validation
      include RRA::DescendantRegistry

      register_descendants RRA, :journal_validations, name_capture: NAME_CAPTURE

      attr_reader :transformer

      # TODO: This default, should maybe come from RRA.app..
      def initialize(transformer)
        super
        @transformer = transformer
      end

      def validate_no_transactions(with_error_msg, *args)
        ledger_opts = args.last.is_a?(Hash) ? args.pop : {}

        results = pta_adapter.register(*args, { file: transformer.output_file }.merge(ledger_opts))

        transactions = block_given? ? yield(results.transactions) : results.transactions

        error_citations = transactions.map do |posting|
          format '%<date>s: %<payee>s', date: posting.date.to_s, payee: posting.payee
        end

        error! with_error_msg, error_citations unless error_citations.empty?
      end

      def validate_no_balance(with_error_msg, account)
        results = pta_adapter.balance account, file: transformer.output_file

        error_citations = results.accounts.map do |ra|
          ra.amounts.map { |commodity| [ra.fullname, RRA.pastel.red('━'), commodity.to_s].join(' ') }
        end

        error_citations.flatten!

        error! with_error_msg, error_citations unless error_citations.empty?
      end
    end

    # This base class is intended for use by inheritors, and contains most of the
    # logic needed, to implement the validation of a system file
    class SystemValidation < Validation
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
end
