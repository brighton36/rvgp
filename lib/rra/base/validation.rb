# frozen_string_literal: true

require_relative '../application/descendant_registry'

module RRA
  module Base
    # This class contains methods shared by both {RRA::Base::JournalValidation} and {RRA::Base::SystemValidation}.
    # Validations are run during a project build, after the reconcile tasks.
    #
    # Validations are typically defined inside a .rb in your project's app/validations folder, and should inherit from
    # JournalValidation or SystemValidation (though not this class itself). Your validations can be customized
    # in ruby, to add warnings or errors to your build. Warnings are non-fatal, and merely output a notice on the
    # command line. Errors are fatal, and halt a build.
    #
    # This Base class contains some common helpers for use in your validations, regardless of whether its a system or
    # journal validation. Here are the differences between these two validation classes:
    #
    # =Journal Validations
    # Validate the output of one reconciler at a time<br>
    #
    # These validations are run immediately after the reconcile task, and before system validations
    # are run. Each instance of these validations is applied to a reconcilers output file (typically located in
    # build/journal). And by default, any journal validations that are defined in a project's app/validations are
    # instantiated against every reconciler's output, in the project. This behavior can be overwritten, by defining a
    # 'disable_checks' array in the root of the reconciler's yaml, containing the name(s) of validations to disable
    # for that journal. These names are expected to be the classname of the validation, underscorized, lowercase, and
    # with the 'Validation' suffix removed from the class. For example, to disable the
    # {RRA::Validations::BalanceValidation} in one of the reconcilers of your project, add the following lines to its
    # yaml:
    #   disable_checks:
    #     - balance
    # A JournalValidation is passed the reconciler corresponding to it's instance in its initialize method. For further
    # details on how these validations work, see the documentation for this class here {RRA::Base::JournalValidation} or
    # check out an example implementation. Here's the BalanceValidation itself, which is a relatively easy example to
    # {https://github.com/brighton36/rra/blob/main/lib/rra/validations/balance_validation.rb balance_validation.rb}
    # follow.
    #
    # =System Validations
    # Validate the entire, finished, journal output for the project <br>
    #
    # Unlike Journal validations, these Validations are run without a target, and are expected to generate warnings and
    # errors based on the state of queries spanning multiple journals.
    #
    # There are no example SystemValidations included in the distribution of rra. However, here's an easy one, to serve
    # as reference. This validation ensures Transfers between accounts are always credited and
    # debited on both sides:
    #  class TransferAccountValidation < RRA::Base::SystemValidation
    #    STATUS_LABEL = 'Unbalanced inter-account transfers'
    #    DESCRIPTION = "Ensure that debits and credits through Transfer accounts, complete without remainders"
    #
    #    def validate
    #      warnings = pta.balance('Transfers').accounts.map do |account|
    #        account.amounts.map do |amount|
    #          [ account.fullname, RRA.pastel.yellow('━'), amount.to_s(commatize: true) ].join(' ')
    #        end
    #      end.compact.flatten
    #
    #      warning! 'Unbalanced Transfer Encountered', warnings if warnings.length > 0
    #    end
    #  end
    #
    # The above validation works, if you assign transfers between accounts like so:
    #   ; This is how a Credit Card Payment looks in my Checking account, the source of funds:
    #   2023-01-25 Payment to American Express card ending in 1234
    #     Transfers:PersonalChecking_PersonalAmex    $ 10000.00
    #     Personal:Assets:AcmeBank:Checking
    #
    #   ; This is how a Credit Card Payment looks in my Amex account, the destination of funds:
    #   2023-01-25 Payment Thank You - Web
    #     Transfers:PersonalChecking_PersonalAmex    $ -10000.00
    #     Personal:Liabilities:AmericanExpress
    #
    # In this format of transfering money, if either the first or second transfer was omitted, the
    # TransferAccountValidation will alert you that money has gone missing somewhere at the bank, and/or is taking
    # longer to complete, than you expected.
    #
    # =Summary of Differences
    # SystemValidations are largely identical to JournalValidations, with, the following exceptions:
    #
    # *Priority*
    # Journal validations are run sooner in the rake process. Just after reconciliations have completed. System
    # validations run immediately after all Journal validations have completed.
    #
    # *Input*
    # Journal validations have one input, accessible via its {RRA::Base::JournalValidation#reconciler}. System
    # validations have no preconfigured inputs at all. Journal Validations support a disable_checks attribute in the
    # reconciler yaml, and system validations have no such directive.
    #
    # *Labeling*
    # With Journal validations, tasks are labeled automatically by rra, based on their class name. System validations
    # are expected to define a STATUS_LABEL and DESCRIPTION constant, in order to arrive at these labels.
    #
    # Note that for either type of validation, most/all of the integration functionality is provided by way of the
    # {RRA::Base::Validation#error!} and {RRA::Base::Validation#warning!} methods, instigated in the class'
    # validate method.
    #
    # =Error and Warning formatting
    # The format of errors and warnings are a bit peculiar, and probably need a bit more polish to the interface.
    # Nonetheless, it's not complicated. Here's the way it works, for both collections:
    # - The formatting of :errors and :warnings is identical. These collections contain a hierarchy of errors, which
    #   is used to display fatal and non-fatal output to the console.
    # - Every element of these collections are expected to be a two element Array. The first element of which is to
    #   be a string containing the topmost error/warning. The second element of this Array is optional. If present,
    #   this second element is expected to be an Array of Strings, which are subordinate to the message in the first
    #   element.
    #
    # @attr_reader [Array<String,Array<String>>] errors Errors encountered by this validation. See the above note on
    #                                                   'Error and Warning formatting'
    # @attr_reader [Array<String,Array<String>>] warnings Warnings encountered by this validation. See the above note on
    #                                                     'Error and Warning formatting'
    class Validation
      include RRA::Pta::AvailabilityHelper

      # @!visibility private
      NAME_CAPTURE = /([^:]+)Validation\Z/.freeze

      attr_reader :errors, :warnings

      # Create a new Validation
      def initialize
        @errors = []
        @warnings = []
      end

      # Returns true if there are no warnings or errors present in this validation's instance. Otherwise, returns false.
      # @return [TrueClass, FalseClass] whether this validation has passed
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
      # Add an error to our {RRA::Base::Validation#errors} collection. The format of this error is expected to match the
      # formatting indicated in the 'Error and Warning formatting' above.
      # @param msg [String] A description of the error.
      # @param citations [Array<String>] Supporting details, subordinate error citations, denotated 'below' the :msg
      def error!(msg, citations = nil)
        @errors << format_error_or_warning(msg, citations)
      end

      # @!visibility public
      # Add a warning to our {RRA::Base::Validation#warnings} collection. The format of this warning is expected to
      # match the formatting indicated in the 'Error and Warning formatting' above.
      # @param msg [String] A description of the warning.
      # @param citations [Array<String>] Supporting details, subordinate warning citations, denotated 'below' the :msg
      def warning!(msg, citations = nil)
        @warnings << format_error_or_warning(msg, citations)
      end
    end

    # A base class, from which your journal validations should inherit. For more information on validations, and your
    # options, see the documentation notes on {RRA::Base::JournalValidation}.
    # @attr_reader [RRA::Reconcilers::CsvReconciler,RRA::Reconcilers::JournalReconciler] reconciler
    #   The reconciler whose output will be inspected by this journal validation instance.
    class JournalValidation < Validation
      include RRA::Application::DescendantRegistry

      register_descendants RRA, :journal_validations, name_capture: NAME_CAPTURE

      attr_reader :reconciler

      # Create a new Journal Validation
      # @param [RRA::Reconcilers::CsvReconciler,RRA::Reconcilers::JournalReconciler] reconciler
      #    see {RRA::Base::JournalValidation#reconciler}
      def initialize(reconciler)
        super()
        @reconciler = reconciler
      end

      # This helper method will supply the provided arguments to pta.register. And if there are any transactions
      # returned, the supplied error message will be added to our :errors colection, citing the transactions
      # that were encountered.
      # @param [String] with_error_msg A description of the error that corresponds to the returned transactions.
      # @param [Array<Object>] args These arguments are supplied directly to {RRA::Pta::AvailabilityHelper#pta}'s
      #                             #register method
      def validate_no_transactions(with_error_msg, *args)
        ledger_opts = args.last.is_a?(Hash) ? args.pop : {}

        results = pta.register(*args, { file: reconciler.output_file }.merge(ledger_opts))

        transactions = block_given? ? yield(results.transactions) : results.transactions

        error_citations = transactions.map do |posting|
          format '%<date>s: %<payee>s', date: posting.date.to_s, payee: posting.payee
        end

        error! with_error_msg, error_citations unless error_citations.empty?
      end

      # This helper method will supply the provided account to pta.balance. And if there is a balance returned,
      # the supplied error message will be added to our :errors colection, citing the balance that was encountered.
      # @param [String] with_error_msg A description of the error that corresponds to the returned balances.
      # @param [Array<String>] account This arguments is supplied directly to {RRA::Pta::AvailabilityHelper#pta}'s
      #                                #balance method
      def validate_no_balance(with_error_msg, account)
        results = pta.balance account, file: reconciler.output_file

        error_citations = results.accounts.map do |ra|
          ra.amounts.map { |commodity| [ra.fullname, RRA.pastel.red('━'), commodity.to_s].join(' ') }
        end

        error_citations.flatten!

        error! with_error_msg, error_citations unless error_citations.empty?
      end
    end

    # A base class, from which your system validations should inherit. For more information on validations, and your
    # options, see the documentation notes on {RRA::Base::JournalValidation}.
    class SystemValidation < Validation
      include RRA::Application::DescendantRegistry

      task_names = ->(registry) { registry.names.map { |name| format('validate_system:%s', name) } }
      register_descendants RRA, :system_validations,
                           name_capture: NAME_CAPTURE,
                           accessors: { task_names: task_names }

      # @!visibility private
      def mark_validated!
        FileUtils.touch self.class.build_validation_file_path
      end

      # @!visibility private
      def self.validated?
        FileUtils.uptodate? build_validation_file_path, [
          RRA.app.config.build_path('journals/*.journal'),
          RRA.app.config.project_path('journals/*.journal')
        ].map { |glob| Dir.glob glob }.flatten
      end

      # @!visibility private
      def self.status_label
        const_get :STATUS_LABEL
      end

      # @!visibility private
      def self.description
        const_get :DESCRIPTION
      end

      # @!visibility private
      def self.build_validation_file_path
        RRA.app.config.build_path(format('journals/system-validation-%s.valid', name.to_s))
      end
    end
  end
end
