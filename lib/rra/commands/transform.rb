# frozen_string_literal: true

module RRA
  module Commands
    # This class contains the dispatch logic of the 'transform' command and task.
    class Transform < RRA::Base::Command
      accepts_options OPTION_ALL, OPTION_LIST, %i[stdout s], %i[concise c]

      include RakeTask
      rake_tasks :transform

      def initialize(*args)
        super(*args)

        if %i[stdout concise].all? { |output| options[output] }
          @errors << I18n.t('commands.transform.errors.either_concise_or_stdout')
        end
      end

      def execute!
        RRA.app.ensure_build_dir! 'journals' unless options[:stdout]
        options[:stdout] || options[:concise] ? execute_each_target : super
      end

      # This class represents a transformer. See RRA::Base::Command::TransformerTarget, for
      # most of the logic that this class inherits. Typically, these targets take the form
      # of "#\\{year}-#\\{transformer_name}"
      class Target < RRA::Base::Command::TransformerTarget
        for_command :transform

        def description
          I18n.t 'commands.transform.target_description', input_file: @transformer.input_file
        end

        def uptodate?
          @transformer.uptodate?
        end

        def execute(options)
          if options[:stdout]
            puts @transformer.to_ledger
          else
            @transformer.to_ledger!
          end

          nil
        end
      end
    end
  end
end
