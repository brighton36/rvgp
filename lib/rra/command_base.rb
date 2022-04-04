require_relative '../rra'
require_relative 'descendant_registry'

class RRA::CommandBase

  class TargetBase
    attr_reader :name, :status_name, :description

    def initialize(name)
      @name = name
    end

    def matches?(by_identifier)
      name == by_identifier
    end

    def self.from_s(str)
      all.find{ |target| target.matches? str }
    end
  end

  class TransformerTarget < RRA::CommandBase::TargetBase
    def initialize(transformer)
      @transformer, @name, @status_name = transformer, transformer.as_taskname,
        transformer.label
    end

    def matches?(by_identifier)
      @transformer.matches_argument? by_identifier
    end

    def description
      I18n.t 'commands.%s.target_description' % self.class.command, 
        input_file: @transformer.input_file
    end

    def self.all
      RRA.app.transformers.collect{|transformer| self.new transformer}
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

  class Option
    class UnexpectedEndOfArgs < StandardError; end

    attr_reader :short, :long

    def initialize(long, short, options = {})
      @short, @long = short.to_sym, long.to_sym
      @has_value = options[:has_value] if options.has_key? :has_value
    end

    def matches?(str)
      ('--%s' % [long.to_s]) == str || ('-%s' % [short.to_s]) == str
    end

    def has_value?
      !@has_value.nil?
    end

    def self.remove_options_from_args(options, args)
      ret_args = []
      ret_options = {}

      i = 0
      until i >= args.length
        arg, arg_value = args[i], nil

        arg, arg_value = $1, $2 if /\A([^\=]+)\=([^ ]+)/.match arg

        option = options.find{ |option| option.matches? arg }

        if option
          ret_options[option.long] = if option.has_value?
            unless arg_value.nil?
              arg_value
            else
              if i+1 >= args.length
                raise UnexpectedEndOfArgs, I18n.t('error.end_of_args') 
              end
              i+=1
              args[i]
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

  include RRA::DescendantRegistry

  register_descendants RRA, :commands

  attr_reader :errors, :options, :targets

  OPTION_ALL  = [:all, :a]
  OPTION_LIST = [:list, :l]

  def initialize(*args)
    @errors, @options, @targets = [], {}, []

    klass_options = self.class.options || []

    # We'll cast the arguments to one of these, instead of storing strings
    target_klass = self.class.const_get('Target')

    @options, remainders = Option.remove_options_from_args self.class.options,
      args

    missing_targets = []
    remainders.each do |remainder|
      if target_klass
        target = target_klass.from_s remainder

        if target
          @targets << target
        else
          missing_targets << remainder
        end
      else
        @targets << remainder
      end
    end

    if options[:list] and target_klass
      indent = I18n.t('status.indicators.indent')
      puts ([RRA.pastel.bold(I18n.t('commands.%s.list_targets' % self.class.name))]+
        target_klass.all.collect{|target| indent+target.name }).join("\n")
      exit
    end

    @targets = target_klass.all if options[:all] and target_klass

    @errors << I18n.t( 'error.no_targets' ) unless @targets.length > 0
    @errors << I18n.t( 'error.missing_target', 
      targets: missing_targets.join(', ') ) if missing_targets.length > 0
  end

  def valid?
    errors.length == 0
  end

  def execute!
    execute_each_target
  end

  private

  def execute_each_target
    # This keeps things DRY for the case of commands such as transform, which
    # use the stdout option
    targets.each{ |target| target.execute options }
  end

  class << self
    def accepts_options(*from_args)
      @options = from_args.collect{|args| Option.new *args }
    end

    def options
      @options || []
    end
  end
end

module RRA::CommandBase::RakeTask

  def execute!
    targets.collect do |target|
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

  module ClassMethods
    attr_reader :rake_namespace

    def rake_tasks(namespace)
      @rake_namespace = namespace
    end

    def initialize_rake(rake_main)
      command_klass = self

      rake_main.instance_eval do 
        namespace command_klass.rake_namespace do 
          command_klass.const_get('Target').all.each do |target|
            desc target.description
            task target.name do
              error_count = 0
              command = command_klass.new target.name

              begin
                rets = command.execute!
                raise StandardError, "This should never happen" if rets.length > 1
                error_count += rets[0][:errors].length
              end unless target.uptodate?

              # NOTE: It would be kind of nice, IMO, if the namespace continued
              # to run, and then failed. Instead of having all tasks in the 
              # namespace halt, on an error. I don't know how to do this, without
              # a lot of monkey patching and such. 
              # Or, maybe, we could just not use multitask() and instead write
              # our own multitasking loop, which, is a similar pita
              abort if error_count > 0
            end
          end
        end
      end if rake_namespace
    end
  end
end
