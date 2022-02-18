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
        # Let's start parsing args:

        # NOTE: There's a kind of outstanding 'bug' here, where, any commands
        # that have -d or --help options would be picked up by the global
        # handling here. The solution is not to have -d or --help in your 
        # local commands. We don't detect that atm, but we may want to at some
        # point. For now, just, don't use these options
        options, command_args = RRA::CommandBase::Option.remove_options_from_args [
          [:help, :h], [:dir, :d, {has_value: true}]
          ].collect{|args| RRA::CommandBase::Option.new(*args) }, args

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
            #
            # Load up the built-in commands:
            require_files!

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

        # If we were able to load the project directory, and help was requested,
        # we offer help here, as we can show them help for their user defined
        # commands, at this time:
        RRA::Commands.help! if options[:help]

        # Dispatch the command:
        command_name = command_args.shift
        command_klass = RRA.commands.find{ |klass| klass.name == command_name }

        error! 'error.unexpected_argument', arg: command_klass unless command_klass

        if command_klass.nil?
          error! 'error.missing_command'
        elsif command_klass
          command = command_klass.new *command_args
          if command.valid?
            command.execute!
          else
            puts RRA.pastel.bold(
              I18n.t("error.command_errors", command: command_klass.name))
            command.errors.each do |error|
              puts RRA.pastel.red(I18n.t('error.command_error', error: error))
            end
          end
        else 
          error! 'error.command_unrecognized', command: command_klass.name
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
