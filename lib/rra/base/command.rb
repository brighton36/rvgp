# frozen_string_literal: true

require_relative '../../rra'
require_relative '../application/descendant_registry'

module RRA
  module Base
    # If you're looking to write your own rra commands, or if you wish to add a rake task - this is the start of that
    # endeavor.
    #
    # All of the built-in rra commands are descendants of this Base class. And, the easiest way to get started in
    # writing your own, is simply to emulate one of these examples. You can see links to these examples listed under
    # {RRA::Commands}.
    #
    # When you're ready to start typing out your code, just place this code in a .rb file under the app/commands
    # directory of your project - and rra will pick it up from there. An instance of a Command, that inherits from
    # this base, is initialized with the parsed contents of the command line, for any case when a user invokes the
    # command by its name on the CLI.
    #
    # The content below documents the argument handling, rake workflow, and related functionality available to you
    # in your commands.
    # @attr_reader [Array<String>] errors This array contains any errors that were encountered, when attempting to
    #                                     initialize this command.
    # @attr_reader [Hash<Symbol,TrueClass, String>] options A hash of pairs, with keys being set to the 'long' form
    #                                                       of any options that were passed on the command line. And
    #                                                       with values consisting of either 'string' (for the case
    #                                                       of a ''--option=value') or 'True' for the prescense of
    #                                                       an option in the short or long form ("-l" or "--long")
    # @attr_reader [<Object>] targets The parsed targets, that were encountered, for this command. Note that this Array
    #                                 may contain just about any object whatsoever, depending on how the Target for
    #                                 a command is written.
    class Command
      # Targets are, as the name would imply, a command line argument, that isn't prefixed with one or more dashes.
      # Whereas some arguments are program options, targets are typically a specific subject or destination, which
      # the command is applied to.
      #
      # This base class offers common functions for navigating targets, and identifying targets on the command line.
      # This is a base class, which would generally find an inheritor inside a specific command's implementation.
      # @attr_reader [String] name The target name, as it would be expected to be found on the CLI
      # @attr_reader [String] status_name The target name, as it would be expected to appear in the status output,
      #                                   which is generally displayed during the processing of this target during
      #                                   the rake process and/or during an rra-triggered process.
      # @attr_reader [String] description A description of this target. Mostly this is used by rake, to describe
      #                                   this target in the 'rake -T' output.
      class Target
        attr_reader :name, :status_name, :description

        # Create a new Target
        # @param [String] name see {RRA::Base::Command::Target#name}
        # @param [String] status_name see {RRA::Base::Command::Target#status_name}
        def initialize(name, status_name = nil)
          @name = name
          @status_name = status_name
        end

        # Returns true, if the provided identifier matches this target
        # @param [String] identifier A target that was encountered on the CLI
        # @return [TrueClass, FalseClass] whether we're the target specified
        def matches?(identifier)
          File.fnmatch? identifier, name
        end

        # Find the target that matches the provided string
        # @param [String] str A string which expresses which needle, we want to find, in this haystack.
        # @return [Target] The target we matched this string against.
        def self.from_s(str)
          all.find_all { |target| target.matches? str }
        end
      end

      # This is an implementation of Target, that matches Reconcilers.
      #
      # This class allows any of the current project's reconcilers to match a target. And, such targets can be selected
      # by way of a:
      # - full reconciler path
      # - reconciler file basename (without the full path)
      # - the reconciler's from field
      # - the reconciler's label field
      # - the reconciler's input file
      # - the reconciler's output file
      #
      # Any class that operates by way of a reconciler-defined target, can use this implementation, in lieu of
      # re-implementing the wheel.
      class ReconcilerTarget < RRA::Base::Command::Target
        # Create a new ReconcilerTarget
        # @param [RRA::Base::Reconciler] reconciler An instance of either {RRA::Reconcilers::CsvReconciler}, or
        #                                             {RRA::Reconcilers::JournalReconciler}, to use as the basis
        #                                             for this target.
        def initialize(reconciler)
          super reconciler.as_taskname, reconciler.label
          @reconciler = reconciler
        end

        # (see RRA::Base::Command::Target#matches?)
        def matches?(identifier)
          @reconciler.matches_argument? identifier
        end

        # (see RRA::Base::Command::Target#description)
        def description
          I18n.t format('commands.%s.target_description', self.class.command), input_file: @reconciler.input_file
        end

        # All possible Reconciler Targets that the project has defined.
        # @return [Array<RRA::Base::Command::ReconcilerTarget>] A collection of targets.
        def self.all
          RRA.app.reconcilers.map { |reconciler| new reconciler }
        end

        # This is a little goofy. But, it exists as a hack to support dispatching this target via the
        # {RRA::Base::Command::ReconcilerTarget.command} method. You can see an example of this at work in the
        # {https://github.com/brighton36/rra/blob/main/lib/rra/commands/reconcile.rb reconcile.rb} file.
        # @param [Symbol] underscorized_command_name The command to return, when
        #                                            {RRA::Base::Command::ReconcilerTarget.command} is called.
        def self.for_command(underscorized_command_name)
          @for_command = underscorized_command_name
        end

        # Returns which command this class is defined for. See the note in
        # #{RRA::Base::Command::ReconcilerTarget.for_command}.
        # @return [Symbol] The command this target is relevant for.
        def self.command
          @for_command
        end
      end

      # This is an implementation of Target, that matches Plots.
      #
      # This class allows any of the current project's plots, to match a target, based on their name and variants.
      #
      # Any class that operates by way of a plot-defined target, can use this implementation, in lieu of
      # re-implementing the wheel.
      # @attr_reader [RRA::Plot] plot An instance of the plot that offers our :name variant
      class PlotTarget < RRA::Base::Command::Target
        attr_reader :plot

        # Create a new PlotTarget
        # @param [String] name A plot variant
        # @param [RRA::Plot] plot A plot instance which will handle this variant
        def initialize(name, plot)
          super name, name
          @plot = plot
        end

        # @!visibility private
        def description
          I18n.t 'commands.plot.target_description', name: name
        end

        # @!visibility private
        def uptodate?
          # I'm not crazy about listing the extension here. Possibly that should come
          # from the plot object. It's conceivable in the future, that we'll use
          # more than one extension here...
          FileUtils.uptodate? @plot.output_file(@name, 'gpi'), [@plot.path] + @plot.variant_files(@name)
        end

        # All possible Plot Targets that the project has defined.
        # @return [Array<RRA::Base::Command::PlotTarget>] A collection of targets.
        def self.all
          RRA::Plot.all(RRA.app.config.project_path('app/plots')).map do |plot|
            plot.variants.map { |params| new params[:name], plot }
          end.flatten
        end
      end

      # Option(s) are, as the name would imply, a command line option, that is prefixed with one or more dashes.
      # Whereas some arguments are program targets, options typically expresses a global program setting, to take
      # effect during this execution.
      #
      # Some options are binaries, and are presumed 'off' if unspecified. Other options are key/value pairs, separated
      # by an equal sign or space, in a form such as "-d ~/ledger" or "--dir=~/ledger". Option keys are expected to
      # exist in both a short and long form. In the previous example, both the "-d" and "--dir" examples are identical.
      # The "-d" form is a short form and "--dir" is a long form, of the same Option.
      #
      # This class offers common functions for specifying and parsing options on the command line, as well as
      # for producing the documentation on an option.
      # @attr_reader [Symbol] short A one character code, which identifies this option
      # @attr_reader [Symbol] long A multi-character code, which identifies this option
      class Option
        # This error is raised when an option is encountered on the CLI, and the string terminated, before a value
        # could be parsed.
        class UnexpectedEndOfArgs < StandardError; end

        attr_reader :short, :long

        # Create a new Option
        # @param [String] short see {RRA::Base::Command::Option#short}
        # @param [String] long see {RRA::Base::Command::Option#long}
        # @param [Hash] options additional parameters to configure this Option with
        # @option options [TrueClass,FalseClass] :has_value (false) This flag indicates that this option is expected to
        #                                                        have a corresponding value, for its key.
        def initialize(long, short, options = {})
          @short = short.to_sym
          @long = long.to_sym
          @has_value = options[:has_value] if options.key? :has_value
        end

        # Returns true, if either our short or long form, equals the provided string
        # @param [String] str an option. This is expected to include one or more dashes.
        # @return [TrueClass,FalseClass] Whether or not we can handle the provided option.
        def matches?(str)
          ["--#{long}", "-#{short}"].include? str
        end

        # Returns true, if we expect our key to be paired with a value. This property is specified in the :has_value
        # option in the constructor.
        # @return [TrueClass,FalseClass] Whether or not we expect a pair
        def value?
          !@has_value.nil?
        end

        # Given program arguments, and an array of options that we wish to support, return the options and arguments
        # that were encountered.
        # @param [Array<RRA::Base::Command::Option>] options The options to that we want to parse, from out of the
        #                                                    provided args
        # @param [Array<String>] args Program arguments, as would be provided by a typical ARGV
        # @return [Array<Hash<Symbol,Object>,Array<String>>] A two-element array. The first element is a Hash of Symbols
        #                                                    To Objects (Either TrueClass or String). The second is an
        #                                                    Array of Strings. The first element represents what options
        #                                                    were parsed, with the key for those options being
        #                                                    represented by their :long form (regardless of what was
        #                                                    encountered) The second element contains the targets that
        #                                                    were encountered.
        def self.remove_options_from_args(options, args)
          ret_args = []
          ret_options = {}

          i = 0
          until i >= args.length
            arg = args[i]
            arg_value = nil

            if /\A([^=]+)=([^ ]+)/.match arg
              arg = ::Regexp.last_match 1
              arg_value = ::Regexp.last_match 2
            end

            option = options.find { |opt| opt.matches? arg }

            if option
              ret_options[option.long] = if option.value?
                                           if arg_value.nil?
                                             if i + 1 >= args.length
                                               raise UnexpectedEndOfArgs, I18n.t('error.end_of_args')
                                             end

                                             i += 1
                                             args[i]
                                           else
                                             arg_value
                                           end
                                         else
                                           true
                                         end
            else
              ret_args << args[i]
            end

            i += 1
          end

          [ret_options, ret_args]
        end
      end

      include RRA::Application::DescendantRegistry

      register_descendants RRA, :commands

      attr_reader :errors, :options, :targets

      # This is shortcut to a --all/-a option, which is common across the built-in rra commands
      OPTION_ALL  = %i[all a].freeze
      # This is shortcut to a --list/-l option, which is common across the built-in rra commands
      OPTION_LIST = %i[list l].freeze

      # Create a new Command, suitable for execution, and initialized with command line arguments.
      # @param [Array<String>] args The arguments that will govern this command's execution, as they would be expected
      #                              to be found in ARGV.
      def initialize(*args)
        @errors = []
        @options = {}
        @targets = []

        # We'll cast the arguments to one of these, instead of storing strings
        target_klass = self.class.const_get('Target')

        @options, remainders = Option.remove_options_from_args self.class.options, args

        missing_targets = []
        remainders.each do |remainder|
          if target_klass
            targets = target_klass.from_s remainder

            if targets
              @targets += targets
            else
              missing_targets << remainder
            end
          else
            @targets << remainder
          end
        end

        if options[:list] && target_klass
          indent = I18n.t 'status.indicators.indent'
          puts ([RRA.pastel.bold(I18n.t(format('commands.%s.list_targets', self.class.name)))] +
            target_klass.all.map { |target| indent + target.name }).join("\n")
          exit
        end

        @targets = target_klass.all if options[:all] && target_klass

        @errors << I18n.t('error.no_targets') if @targets.empty?
        @errors << I18n.t('error.missing_target', targets: missing_targets.join(', ')) unless missing_targets.empty?
      end

      # Indicates whether we can execute this command, given the provided arguments
      # @return [TrueClass,FalseClass] Returns true if there were no problems during initialization
      def valid?
        errors.empty?
      end

      # Executes the command, using the provided options, for each of the targets provided.
      # @return [void]
      def execute!
        execute_each_target
      end

      private

      def execute_each_target
        # This keeps things DRY for the case of commands such as reconcile, which
        # use the stdout option
        targets.each { |target| target.execute options }
      end

      class << self
        # This method exists as a shortcut for inheriting classes, to use, in defining what options their command
        # supports. This method expects a variable amount of arrays. With, each of those arrays
        # expected to contain a :short and :long symbol, and optionally a third Hash element, specifying initialize
        # options.
        #
        # Each of these arguments are supplied to {RRA::Base::Command::Option#initialize}.
        # {RRA::Base::Command::OPTION_ALL} and {RRA::Base::Command::OPTION_LIST} are common parameters to supply as
        # arguments to this method.
        # @param [Array<Array<Symbol,Hash>>] args An array, of pairs of [:long, :short] Symbol(s).
        def accepts_options(*args)
          @options = args.map { |option_args| Option.new(*option_args) }
        end

        # Return the options that have been defined for this command
        # @return [Array<RRA::Base::Command::Option] the options this command handles
        def options
          @options || []
        end
      end

      # This module contains helpers methods, for commands, that want to be inserted into the rake process. By including
      # this module in your command, you'll gain access to {RRA::Base::Command::RakeTask::ClassMethods#rake_tasks},
      # which will append the Target(s) of your command, to the rake process.
      #
      # If custom rake declarations are necessary for your command the
      # {RRA::Base::Command::RakeTask::ClassMethods#initialize_rake} method can be overridden, in order to make those
      # declarations.
      #
      # Probably you should just head over to {RRA::Base::Command::RakeTask::ClassMethods} to learn more about this
      # module.
      module RakeTask
        # @!visibility private
        def execute!
          targets.map do |target|
            RRA.app.logger.info self.class.name, target.status_name do
              warnings, errors = target.execute options
              warnings ||= []
              errors ||= []
              { warnings: warnings, errors: errors }
            end
          end
        end

        # @!visibility private
        def self.included(klass)
          klass.extend ClassMethods
        end

        # These methods are automatically included by the RakeTask module, and provide
        # helper methods, to the class itself, of the command that RakeTask was included
        # in.
        module ClassMethods
          # The namespace in which this command's targets are defined. This value is
          # set by {RRA::Base::Command::RakeTask::ClassMethods#rake_tasks}.
          attr_reader :rake_namespace

          # This method is provided for classes that include this module. Calling this method, with a namespace,
          # ensures that all the targets in the command, are setup as rake tasks inside the provided namespace.
          # @param [Symbol] namespace A prefix, under which this command's targets will be declared in rake.
          # @return [void]
          def rake_tasks(namespace)
            @rake_namespace = namespace
          end

          # @!visibility private
          def task_exec(target)
            error_count = 0
            command = new target.name

            unless target.uptodate?
              rets = command.execute!
              raise StandardError, 'This should never happen' if rets.length > 1

              if rets.empty?
                raise StandardError, format('The %<command>s command aborted when trying to run the %<task>s task',
                                            command: command.class.name,
                                            task: task.name)

              end

              error_count += rets[0][:errors].length
            end

            # NOTE: It would be kind of nice, IMO, if the namespace continued
            # to run, and then failed. Instead of having all tasks in the
            # namespace halt, on an error. I don't know how to do this, without
            # a lot of monkey patching and such.
            # Or, maybe, we could just not use multitask() and instead write
            # our own multitasking loop, which, is a similar pita
            abort if error_count.positive?
          end

          # This method initializes rake tasks in the provided context. This method exists as a default implementation
          # for commands, with which to initialize their rake tasks. Feel free to overload this default behavior in your
          # commands.
          # @param [main] rake_main Typically this is the environment of a Rakefile that was passed onto us via self.
          # @return [void]
          def initialize_rake(rake_main)
            command_klass = self

            if rake_namespace
              rake_main.instance_eval do
                namespace command_klass.rake_namespace do
                  command_klass.const_get('Target').all.each do |target|
                    unless Rake::Task.task_defined?(target.name)
                      desc target.description
                      task(target.name) { |_task, _task_args| command_klass.task_exec(target) }
                    end
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end
