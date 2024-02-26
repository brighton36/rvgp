# frozen_string_literal: true

require_relative 'base/command'

module RVGP
  # This module contains the implementation of each task in the rake process.
  # However, these commands aren't documented yet. And, may never be. They're
  # mostly not useful for any api purpose. Documentation for each of these
  # commands is available via `rvgp --help`.
  #
  # However, these files are really useful examples to review, if you want to
  # create rake tasks and/or custom rvgp commands in your projects. Take a look
  # at the source code, for easy implementations that you can follow:
  # - {https://github.com/brighton36/rvgp/blob/main/lib/rvgp/commands/cashflow.rb cashflow.rb}
  # - {https://github.com/brighton36/rvgp/blob/main/lib/rvgp/commands/grid.rb grid.rb}
  # - {https://github.com/brighton36/rvgp/blob/main/lib/rvgp/commands/new_project.rb new_project.rb}
  # - {https://github.com/brighton36/rvgp/blob/main/lib/rvgp/commands/plot.rb plot.rb}
  # - {https://github.com/brighton36/rvgp/blob/main/lib/rvgp/commands/publish_gsheets.rb publish_gsheets.rb}
  # - {https://github.com/brighton36/rvgp/blob/main/lib/rvgp/commands/ireconcile.rb ireconcile.rb}
  # - {https://github.com/brighton36/rvgp/blob/main/lib/rvgp/commands/reconcile.rb reconcile.rb}
  # - {https://github.com/brighton36/rvgp/blob/main/lib/rvgp/commands/validate_journal.rb validate_journal.rb}
  # - {https://github.com/brighton36/rvgp/blob/main/lib/rvgp/commands/validate_system.rb validate_system.rb}
  #
  # The 'new_project.rb is a bit of a special case, due to it being the only command that's available in the
  # absensce of a 'current project'. And, as such, might not be the best example to emulate...
  module Commands
    class << self
      # @!visibility private
      def require_files!
        Dir.glob([File.dirname(__FILE__), 'commands', '*.rb'].join('/')).sort.each { |file| require file }
      end

      # @!visibility private
      def dispatch!(*args)
        # Let's start parsing args:

        # NOTE: There's a kind of outstanding 'bug' here, where, any commands
        # that have -d or --help options would be picked up by the global
        # handling here. The solution is not to have -d or --help in your
        # local commands. We don't detect that atm, but we may want to at some
        # point. For now, just, don't use these options
        options, command_args = RVGP::Base::Command::Option.remove_options_from_args(
          [%i[help h], [:dir, :d, { has_value: true }]].map { |a| RVGP::Base::Command::Option.new(*a) },
          args
        )

        command_name = command_args.shift

        # Process global options:
        app_dir = if options[:dir]
                    options[:dir]
                  elsif ENV.key? 'LEDGER_FILE'
                    File.dirname ENV['LEDGER_FILE']
                  end

        # I'm not crazy about this implementation, but, it's a special case. So,
        # we dispatch the new_project command in this way:
        if command_name == 'new_project'
          require_files!
          dispatch_klass RVGP::Commands::NewProject, app_dir
          exit
        end

        unless app_dir && File.directory?(app_dir)
          # To solve the chicken and the egg problem, that's caused by
          # user-defined commands adding to our help. We have two ways of
          # handling the help. Here, we display the help, even if there's no app_dir:
          if options[:help]
            # This will only show the help for built-in commands, as we were
            # not able to load the project_dir's commands
            require_files!
            RVGP::Commands.help!
          else
            error! 'error.no_application_dir', dir: app_dir
          end
        end

        # Initialize the provided app:
        begin
          RVGP.initialize_app app_dir unless command_name == 'new_project'
        rescue RVGP::Application::InvalidProjectDir
          error! 'error.invalid_application_dir', directory: app_dir
        end

        # If we were able to load the project directory, and help was requested,
        # we offer help here, as we can show them help for their user defined
        # commands, at this time:
        RVGP::Commands.help! if options[:help]

        # Dispatch the command:
        command_klass = RVGP.commands.find { |klass| klass.name == command_name }

        if command_name.nil?
          error! 'error.missing_command'
        elsif command_klass
          dispatch_klass command_klass, command_args
        else
          error! 'error.command_unrecognized', command: command_name
        end
      end

      # @!visibility private
      def help!
        # Find the widest option's width, and use that for alignment.
        widest_option = RVGP.commands.map { |cmd| cmd.options.map(&:long) }.flatten.max.length

        indent = I18n.t('help.indent')
        puts [
          I18n.t('help.usage', program: File.basename($PROGRAM_NAME)),
          [indent, I18n.t('help.description')],
          I18n.t('help.command_introduction'),
          I18n.t('help.target_introduction'),
          I18n.t('help.global_option_introduction'),
          I18n.t('help.command_list_introduction'),
          RVGP.commands.map do |command_klass|
            [
              [indent, RVGP.pastel.bold(command_klass.name)].join,
              [indent, I18n.t(format('help.commands.%s.description', command_klass.name))].join,
              if command_klass.options.empty?
                nil
              else
                [nil,
                 command_klass.options.map do |option|
                   [indent * 2,
                    '-', option.short, ', ',
                    format("--%-#{widest_option}s", option.long), ' ',
                    I18n.t(format('help.commands.%<command>s.options.%<option>s',
                                  command: command_klass.name,
                                  option: option.long.to_s))].join
                 end,
                 nil]
              end
            ]
          end
        ].flatten.join "\n"
        exit
      end

      private

      def error!(i18n_key, **options)
        puts [RVGP.pastel.red(I18n.t('error.error')), I18n.t(i18n_key, **options)].join(': ')
        exit 1
      end

      def dispatch_klass(command_klass, command_args)
        command = command_klass.new(*command_args)
        if command.valid?
          command.execute!
        else
          puts RVGP.pastel.bold(I18n.t('error.command_errors', command: command_klass.name))
          command.errors.each do |error|
            puts RVGP.pastel.red(I18n.t('error.command_error', error: error))
          end
          exit 1
        end
      end
    end
  end
end
