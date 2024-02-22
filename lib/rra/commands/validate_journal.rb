# frozen_string_literal: true

module RRA
  module Commands
    # @!visibility private
    # This class contains dispatch logic for the 'validate_journal' command and task.
    class ValidateJournal < RRA::Base::Command
      accepts_options OPTION_ALL, OPTION_LIST

      include RakeTask
      rake_tasks :validate_journal

      # @!visibility private
      # This class principally represents the journals, by way of  the reconciler
      # in which the journal is defined. See RRA::Base::Command::ReconcilerTarget, for
      # most of the logic that this class inherits. Typically, these targets take
      # the form of "#\\{year}-#\\{reconciler_name}"
      class Target < RRA::Base::Command::ReconcilerTarget
        for_command :validate_journal

        # @!visibility private
        def uptodate?
          @reconciler.validated?
        end

        # @!visibility private
        def mark_validated!
          @reconciler.mark_validated!
        end

        # @!visibility private
        def execute(_options)
          disable_checks = @reconciler.disable_checks.map(&:to_sym)

          # Make sure the file exists, before proceeding with anything:
          return [I18n.t('commands.transform.errors.journal_missing')], [] unless File.exist? @reconciler.output_file

          warnings = []
          errors = []

          RRA.journal_validations.classes.each do |klass|
            next if disable_checks.include? klass.name.to_sym

            validation = klass.new @reconciler

            next if validation.valid?

            warnings += validation.warnings
            errors += validation.errors
          end

          @reconciler.mark_validated! if (errors.length + warnings.length).zero?

          [warnings, errors]
        end
      end
    end
  end
end
