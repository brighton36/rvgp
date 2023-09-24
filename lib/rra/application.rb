# frozen_string_literal: true

require_relative 'application/status_output'
require_relative 'application/config'

module RRA
  # The main application class, by which all projects are defined. This class
  # contains the methods and properties that are intrinsic to the early stages of
  # project initialization, and which provides the functionality used by
  # submodules initialized after initialization. In addition, this class implements
  # the main() entry point used by Rakefiles, and in turn, instigates the
  # equivalent entry points in various modules thereafter.
  #
  # @attr_reader [String] project_path The directory path, from which this application was initialized.
  # @attr_reader [RRA::Application::StatusOutputRake] logger The application logger. This is provided so that callers
  #                                             can output to the console. (Or wherever the output device is logging)
  # @attr_reader [RRA::Journal::Pricer] pricer This attribute contains the pricer that's used by the application. Price
  #                                            data is automatically loaded from config.prices_path (typically
  #                                            'journals/prices.db')
  # @attr_reader [RRA::Application::Config] config The application configuration, most of which is parsed from the
  #                                                config.yaml
  class Application
    # This error is thrown when the project_path provided to {Application#initialize} doesn't exist, and/or is
    # otherwise invalid.
    class InvalidProjectDir < StandardError; end

    attr_reader :project_path, :logger, :pricer, :config

    # Creates an instance of Application, given the files and structure of the provided project path.
    # @param project_path [String] The path, to an RRA project directory.
    def initialize(project_path)
      raise InvalidProjectDir unless [project_path, format('%s/app', project_path)].all? { |f| Dir.exist? f }

      @project_path = project_path
      @config = RRA::Application::Config.new project_path
      @logger = RRA::Application::StatusOutputRake.new pastel: RRA.pastel

      if File.exist? config.prices_path
        @pricer = RRA::Journal::Pricer.new(
          File.read(config.prices_path),
          # This 'addresses' a pernicious bug that will likely affect you. And
          # I don't have an easy solution, as, I sort of blame ledger for this.
          # The problem will manifest itself in the form of grids that output
          # differently, depending on what grids were built in the process.
          #
          # So, If, say, we're only building 2022 grids. But, a clean build
          # would have built 2021 grids, before instigating the 2022 grid
          # build - then, we would see different outputs in the 2022-only build.
          #
          # The reason for this, is that there doesn't appear to be any way of
          # accounting for all historical currency conversions in ledger's output.
          # The data coming out of ledger only includes currency conversions in
          # the output date range. This will sometimes cause weird discrepencies
          # in the totals between a 2021-2022 run, vs a 2022-only run.
          #
          # The only solution I could think of, at this time, was to burp on
          # any occurence, where, a conversion, wasn't already in the prices.db
          # That way, an operator (you) can simply add the outputted burp, into
          # the prices.db file. This will ensure consistency in all grids,
          # regardless of the ranges you run them.
          #
          # NOTE: This feature is currently unimplemnted in hledger. And, I have no
          # solution planned there at this time.
          #
          # If you have a better idea, or some way to ensure consistency in... PR's welcome!
          before_price_add: lambda { |time, from_alpha, to|
            puts [
              RRA.pastel.yellow(I18n.t('error.warning')),
              I18n.t('error.missing_entry_in_prices_db', time: time, from: from_alpha, to: to)
            ].join ' '
          }
        )
      end

      # Include all the project files:
      require_commands!
      require_validations!
      require_grids!
    end

    # @return [Array] An array, containing all the transformer objects, defined in the project
    def transformers
      @transformers ||= RRA::Base::Transformer.all project_path
    end

    # This method will insert all the project tasks, into a Rake object.
    # Typically, 'self' is that object, when calling from a Rakefile. (aka 'main')
    # @param rake_main [Object] The Rake object to attach RRA to.
    # @return [void]
    def initialize_rake!(rake_main)
      require 'rake/clean'

      CLEAN.include FileList[RRA.app.config.build_path('*')]

      # This removes clobber from the task list:
      Rake::Task['clobber'].clear_comments

      project_tasks_dir = format('%s/tasks', project_path)
      Rake.add_rakelib project_tasks_dir if File.directory? project_tasks_dir

      RRA.commands.each do |command_klass|
        command_klass.initialize_rake rake_main if command_klass.respond_to? :initialize_rake
      end

      # TODO: I think we should maybe break these into tasks, which multitask within,
      # that way we don't call the grids.task_names here, and instead call that
      # once we've completed the transform/validate/etc
      rake_main.instance_eval do
        multitask transform: RRA.app.transformers.map { |tf| "transform:#{tf.as_taskname}" }
        multitask validate_journal: RRA.app.transformers.map { |tf| "validate_journal:#{tf.as_taskname}" }
        multitask validate_system: RRA.system_validations.task_names
        multitask grid: RRA.grids.task_names

        # NOTE: We really have no way of determininig what plots will be
        # available at program initialization. Mostly, this is because the
        # grids create sheets, based on the results of the build step.
        # So, what we'll do instead, is offer the grids, as plot targets.
        # And let the plot task determine which grids contain which plots

        task default: %i[transform validate_journal validate_system grid plot]
      end
    end

    # This helper method will create the provided subdir inside the project's build/ directory, if that
    # subdir doesn't already exist. In the case that this subdir already exists, the method terminates
    # gracefully, without action.
    # @return [void]
    def ensure_build_dir!(subdir)
      path = RRA.app.config.build_path subdir
      FileUtils.mkdir_p path unless File.directory? path
    end

    private

    def require_commands!
      # Built-in commands:
      RRA::Commands.require_files!

      # App commands:
      require_app_files! 'commands'
    end

    def require_grids!
      require_app_files! 'grids'
    end

    def require_validations!
      # Built-in validations:
      Dir.glob(RRA::Gem.root('lib/rra/validations/*.rb')).sort.each { |file| require file }

      # App validations:
      require_app_files! 'validations'
    end

    def require_app_files!(subdir)
      Dir.glob([project_path, 'app', subdir, '*.rb'].join('/')).sort.each { |file| require file }
    end
  end
end
