# frozen_string_literal: true

require_relative '../../rra'
require_relative '../application/descendant_registry'

module RRA
  module Base
    # The base class, from which all commands inherit. This class contains argument
    # handling code, as well as code to insert the commands into the rake workflow
    # (if appropriate)
    class Command
      # This class serves offers functionality to the targets of commands and rake
      # operations. This class is meant to be inhereted by specific types of targets,
      # and contains helpers and state, used by all target classes
      class Target
        attr_reader :name, :status_name, :description

        def initialize(name, status_name = nil)
          @name = name
          @status_name = status_name
        end

        def matches?(by_identifier)
          File.fnmatch? by_identifier, name
        end

        def self.from_s(str)
          all.find_all { |target| target.matches? str }
        end
      end

      # Methods used to find and select transformers, in the current project directory.
      # This class provides targets for commands that operate on transformers.
      class TransformerTarget < RRA::Base::Command::Target
        def initialize(transformer)
          super transformer.as_taskname, transformer.label
          @transformer = transformer
        end

        def matches?(by_identifier)
          @transformer.matches_argument? by_identifier
        end

        def description
          I18n.t format('commands.%s.target_description', self.class.command), input_file: @transformer.input_file
        end

        def self.all
          RRA.app.transformers.map { |transformer| new transformer }
        end

        # This is a little goofy. But, atm, it mostly lets us DRY up the description
        # method
        def self.for_command(underscorized_command_name)
          @for_command = underscorized_command_name
        end

        def self.command
          @for_command
        end
      end

      # Methods used to find and select plots, in the current project directory.
      # This class provides plots for commands that operate on plots.
      class PlotTarget < RRA::Base::Command::Target
        attr_reader :name, :plot

        def initialize(name, plot)
          super name, name
          @plot = plot
        end

        def uptodate?
          # I'm not crazy about listing the extension here. Possibly that should come
          # from the plot object. It's conceivable in the future, that we'll use
          # more than one extension here...
          FileUtils.uptodate?(
            @plot.output_file(@name, 'gpi'),
            [@plot.path] + @plot.variant_files(@name)
          )
        end

        def self.all
          RRA::Plot.all(RRA.app.config.project_path('app/plots')).map do |plot|
            plot.variants.map { |params| new params[:name], plot }
          end.flatten
        end
      end

      # An argument, passed to the rra executable, which contains one or more -'s at the start.
      # This class defines the expectations that a command has for this format of argument, and
      # this class produces the help output, and parsing code, given this definition.
      class Option
        class UnexpectedEndOfArgs < StandardError; end

        attr_reader :short, :long

        def initialize(long, short, options = {})
          @short = short.to_sym
          @long = long.to_sym
          @has_value = options[:has_value] if options.key? :has_value
        end

        def matches?(str)
          ["--#{long}", "-#{short}"].include? str
        end

        def value?
          !@has_value.nil?
        end

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

      OPTION_ALL  = %i[all a].freeze
      OPTION_LIST = %i[list l].freeze

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

      def valid?
        errors.empty?
      end

      def execute!
        execute_each_target
      end

      private

      def execute_each_target
        # This keeps things DRY for the case of commands such as transform, which
        # use the stdout option
        targets.each { |target| target.execute options }
      end

      class << self
        def accepts_options(*from_args)
          @options = from_args.map { |args| Option.new(*args) }
        end

        def options
          @options || []
        end
      end

      # This module contains helpers methods, for commands, that wish to be inserted
      # into the rake process.
      module RakeTask
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

        def self.included(klass)
          klass.extend ClassMethods
        end

        # These methods are automatically included by the RakeTask module, and provide
        # helper methods, to the class itself, of the command that RakeTask was included
        # by.
        module ClassMethods
          attr_reader :rake_namespace

          def rake_tasks(namespace)
            @rake_namespace = namespace
          end

          def task_exec(target)
            # NOTE: We'd probably be better served by taking the target out of here,
            #       and putting that into the task, or task_args somehow.... then
            #       passing this &function to the task() method, instead of returning
            #       a block...
            lambda { |_task, _task_args|
              error_count = 0
              command = new target.name

              unless target.uptodate?
                rets = command.execute!
                raise StandardError, 'This should never happen' if rets.length > 1

                error_count += rets[0][:errors].length
              end

              # NOTE: It would be kind of nice, IMO, if the namespace continued
              # to run, and then failed. Instead of having all tasks in the
              # namespace halt, on an error. I don't know how to do this, without
              # a lot of monkey patching and such.
              # Or, maybe, we could just not use multitask() and instead write
              # our own multitasking loop, which, is a similar pita
              abort if error_count.positive?
            }
          end

          def initialize_rake(rake_main)
            command_klass = self

            if rake_namespace
              rake_main.instance_eval do
                namespace command_klass.rake_namespace do
                  command_klass.const_get('Target').all.each do |target|
                    desc target.description
                    task target.name, &command_klass.task_exec(target)
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
