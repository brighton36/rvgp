# frozen_string_literal: true

require_relative '../application/descendant_registry'

module RRA
  module Base
    # This class contains methods shared by both {RRA::Base::JournalValidation} and {RRA::Base::SystemValidation}.
    # Validations are run during a project build, after the transform tasks.
    #
    # Validations are typically defined inside a .rb in your project's app/validations folder, and should inherit from
    # JournalValidation or SystemValidation (though not this class itself). Your validations can be customized
    # in ruby, to add warnings or errors to your build. Warnings are non-fatal, and merely output a notice on the
    # command line. Errors are fatal, and halt a build.
    #
    # This Base class contains some common helpers for use in your validations, regardless of whether its a system or
    # journal validation. Here are the differences between these two validation classes:
    #
    # *JournalValidation* - Validate the output of a transform <br>
    # These validations are run immediately after the transform task, and before system validations
    # are run. Each instance of these validations is applied to a transformers output file (typically located in
    # build/journal). And by default, any journal validations that are defined in a project's app/validations are
    # instantiated against every transformer's output, in the project. This behavior can be overwritten, by defining a
    # 'disable_checks' array in the root of the transformer's yaml, containing the name(s) of validations to disable
    # for that journal. These names are expected to be the classname of the validation, underscorized, lowercase, and
    # with the 'Validation' suffix removed from the class. For example, to disable the
    # {RRA::Validations::BalanceValidation} in one of the transformers of your project, add the following lines to its
    # yaml:
    #   disable_checks:
    #     - balance
    # A JournalValidation is passed the transformer corresponding to it's instance in its initialize method. For further
    # details on how these validations work, see the documentation for this class here {RRA::Base::JournalValidation} or
    # check out an example implementation. Here's the BalanceValidation itself, which is a relatively easy example to
    # {https://github.com/brighton36/rra/blob/main/lib/rra/validations/balance_validation.rb balance_validation.rb}
    # follow.
    #
    # *SystemValidation* - Validate the entire, finished, journal output for the project <br>
    # Unlike Journal validations, these Validations are run without a target, and are expected to generate warnings and
    # errors based on the state of queries spanning multiple journals.
    #
    # There are no example SystemValidations included in the distribution of rra. However, here's an easy one, to serve
    # as reference. Here's an easy system validation, that ensures Transfers between accounts are always credited and
    # debited on both sides:
    #  class TransferAccountValidation < RRA::Base::SystemValidation
    #    STATUS_LABEL = 'Unbalanced inter-account transfers'
    #    DESCRIPTION = "Ensure that debits and credits through Transfer accounts, complete without remainders"
    #
    #    def validate
    #      warnings = pta.balance('Transfers').accounts.collect do |account|
    #        account.amounts.collect do |amount|
    #          [ account.fullname, RRA.pastel.yellow('━'), amount.to_s(commatize: true) ].join(' ')
    #        end
    #      end.compact.flatten
    #
    #      warning! 'Unbalanced Transfer%s Encountered' % [(warnings.length > 1) ? 's' : ''], warnings if warnings.length > 0
    #    end
    #  end
    #
    # TODO: Explain the spirit of this thing
    # TODO: Note the constants
    #
    # *NOTE* For either type of validation, most/all of the integration functionality is provided by way of the
    # {RRA::Base::Validation#error!} and {RRA::Base::Validation#warning!} methods, instigated in the class'
    # validate method.
    #
    # @attr_reader [Array<String>] errors TODO
    # @attr_reader [Array<String>] warnings TODO
    class Validation
      include RRA::Pta::AvailabilityHelper

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

      # @!visibility public
      def error!(*args)
        @errors << format_error_or_warning(*args)
      end

      # @!visibility public
      def warning!(*args)
        @warnings << format_error_or_warning(*args)
      end
    end

    # This base class is intended for use by inheritors, and contains most of the
    # logic needed, to implement the validation of a journal file
    class JournalValidation < Validation
      include RRA::Application::DescendantRegistry

      register_descendants RRA, :journal_validations, name_capture: NAME_CAPTURE

      attr_reader :transformer

      # TODO: This default, should maybe come from RRA.app..
      def initialize(transformer)
        super
        @transformer = transformer
      end

      def validate_no_transactions(with_error_msg, *args)
        ledger_opts = args.last.is_a?(Hash) ? args.pop : {}

        results = pta.register(*args, { file: transformer.output_file }.merge(ledger_opts))

        transactions = block_given? ? yield(results.transactions) : results.transactions

        error_citations = transactions.map do |posting|
          format '%<date>s: %<payee>s', date: posting.date.to_s, payee: posting.payee
        end

        error! with_error_msg, error_citations unless error_citations.empty?
      end

      def validate_no_balance(with_error_msg, account)
        results = pta.balance account, file: transformer.output_file

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
      include RRA::Application::DescendantRegistry

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
