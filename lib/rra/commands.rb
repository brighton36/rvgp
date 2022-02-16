require_relative '../rra'
require_relative 'command_base'

module RRA
  module Commands
    class << self
      def require_files!
        Dir.glob('%s/commands/*.rb' % [File.dirname(__FILE__), 'commands']).each do |file|
          require file
        end
      end

      def dispatch!(*args)
        RRA::Commands.require_files!
        # TODO: Project_dir

        # Let's start parsing args:
        arg_command_index = args.find_index{|arg| 
          RRA.commands.find{ |klass| klass.name == arg } }

        if arg_command_index
          arg_command = args[arg_command_index]
          global_args = args[0...arg_command_index]
          command_args = args[(arg_command_index+1)..args.length]
        else
          global_args = args
        end

        options, targets = RRA::CommandBase::Option.remove_options_from_args [
          [:help, :h], [:dir, :d, {has_value: true}]
          ].collect{|args| RRA::CommandBase::Option.new(*args) }, global_args

        error! 'error.unexpected_arguments', args: targets.join(',') if (
          targets.length > 0 )

        # Process global options:
        app_dir = if options[:dir]
          options[:dir]
        elsif ENV.has_key? 'LEDGER_FILE'
          app_dir = File.dirname(ENV['LEDGER_FILE'])
        end

        # To solve the chicken and the egg problem, that's caused by
        # user-defined commands adding to our help. We have two ways of 
        # displaying help. Here, we display the help, if there's no app_dir:
        unless app_dir and File.directory?(app_dir)
          if options[:help]
            # This will only show the help for built-in commands, as we were
            # not able to load the project_dir's commands
            RRA::Commands.help! 
          else
            error! 'error.no_application_dir', dir: app_dir 
          end
        end

        # Initialize the provided app:
        begin
          RRA.initialize_app app_dir
        rescue RRA::Application::InvalidProjectDir
          error! 'error.invalid_application_dir', directory: app_dir
        end

        RRA.app.require_commands!
        RRA.app.require_validations!
        RRA.app.require_reports!

        # If we were able to load the project directory, and help was requested,
        # we offer help here, as we can show them help for their user defined
        # commands, at this time:
        RRA::Commands.help! if options[:help]

        # Dispatch the command:
        command_klass = RRA.commands.find{ |klass| klass.name == arg_command }

        if arg_command.nil?
          error! 'error.missing_command'
        elsif command_klass
          command = command_klass.new *command_args
          if command.valid?
            command.execute!
          else
            puts RRA.pastel.bold(I18n.t("error.command_errors", command: arg_command))
            command.errors.each do |error|
              puts RRA.pastel.red(I18n.t('error.command_error', error: error))
            end
          end
        else 
          error! 'error.command_unrecognized', command: arg_command
        end
      end

      def help!
        # Find the widest option's width, and use that for alignment.
        widest_option = RRA.commands.collect{|cmd| 
          cmd.options.collect(&:long) }.flatten.sort.last.length

        indent = I18n.t('help.indent')
        puts [
          I18n.t('help.usage', program: File.basename($0)),
          [indent, I18n.t('help.description')],
          I18n.t('help.command_introduction'),
          RRA.commands.collect{|command_klass| 
            [
              [ indent, RRA.pastel.bold(command_klass.name)].join,
              [ indent, I18n.t('help.commands.%s.description' % command_klass.name) ].join,
              (command_klass.options.length > 0) ? 
              [nil,
              command_klass.options.collect{|option| 
                [ indent*2, 
                  '-', option.short, ', ',
                  "--%-#{widest_option}s" % option.long, ' ',
                  I18n.t('help.commands.%s.options.%s' % [ command_klass.name, 
                    option.long.to_s ]) 
                ].join
              }, nil] : nil
            ]
          },
          I18n.t('help.global_option_introduction')
        ].flatten.join "\n"
        exit
      end

      def error!(i18n_key, **options)
        puts [RRA.pastel.red(I18n.t('error.error')), 
          I18n.t(i18n_key, **options)].join(': ')
        exit
      end
    end
  end
end
