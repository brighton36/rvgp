# frozen_string_literal: true

module RVGP
  module Commands
    # @!visibility private
    # This class contains the dispatch logic of the 'reconcile' command and task.
    class Reconcile < RVGP::Base::Command
      accepts_options OPTION_ALL, OPTION_LIST, %i[stdout s], %i[concise c]

      include RakeTask
      rake_tasks :reconcile

      # @!visibility private
      def initialize(*args)
        super(*args)

        if %i[stdout concise].all? { |output| options[output] }
          @errors << I18n.t('commands.reconcile.errors.either_concise_or_stdout')
        end
      end

      # @!visibility private
      def execute!
        RVGP.app.ensure_build_dir! 'journals' unless options[:stdout]
        options[:stdout] || options[:concise] ? execute_each_target : super
      end

      # @!visibility private
      # This class represents a reconciler. See RVGP::Base::Command::ReconcilerTarget, for
      # most of the logic that this class inherits. Typically, these targets take the form
      # of "#\\{year}-#\\{reconciler_name}"
      class Target < RVGP::Base::Command::ReconcilerTarget
        for_command :reconcile

        # @!visibility private
        def description
          I18n.t 'commands.reconcile.target_description', input_file: @reconciler.input_file
        end

        # @!visibility private
        def uptodate?
          @reconciler.uptodate?
        end

        # @!visibility private
        def execute(options)
          if options[:stdout]
            puts @reconciler.to_ledger
          else
            @reconciler.to_ledger!
          end

          nil
        end
      end
    end
  end
end
