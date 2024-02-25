# frozen_string_literal: true

require_relative 'application/status_output'
require_relative 'application/config'

module RVGP
  # The main application class, by which all projects are defined. This class
  # contains the methods and properties that are intrinsic to the early stages of
  # project initialization, and which provides the functionality used by
  # submodules initialized after initialization. In addition, this class implements
  # the main() entry point used by Rakefiles, and in turn, instigates the
  # equivalent entry points in various modules thereafter.
  #
  # @attr_reader [String] project_path The directory path, from which this application was initialized.
  # @attr_reader [RVGP::Application::StatusOutputRake] logger The application logger. This is provided so that callers
  #                                             can output to the console. (Or wherever the output device is logging)
  # @attr_reader [RVGP::Journal::Pricer] pricer This attribute contains the pricer that's used by the application. Price
  #                                            data is automatically loaded from config.prices_path (typically
  #                                            'journals/prices.db')
  # @attr_reader [RVGP::Application::Config] config The application configuration, most of which is parsed from the
  #                                                config.yaml
  class Application
    # This error is thrown when the project_path provided to {Application#initialize} doesn't exist, and/or is
    # otherwise invalid.
    class InvalidProjectDir < StandardError; end

    attr_reader :project_path, :logger, :pricer, :config

    # Creates an instance of Application, given the files and structure of the provided project path.
    # @param project_path [String] The path, to an RVGP project directory.
    def initialize(project_path)
      raise InvalidProjectDir unless [project_path, format('%s/app', project_path)].all? { |f| Dir.exist? f }

      @project_path = project_path
      @config = RVGP::Application::Config.new project_path
      @logger = RVGP::Application::StatusOutputRake.new pastel: RVGP.pastel

      if File.exist? config.prices_path
        @pricer = RVGP::Journal::Pricer.new(
          File.read(config.prices_path),
          # See the documentation in RVGP::Journal::Pricer#initialize, to better understand what's happening here.
          # And, Note that this functionality is only supported when ledger is the pta adapter.
          before_price_add: lambda { |time, from_alpha, to|
            puts [
              RVGP.pastel.yellow(I18n.t('error.warning')),
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

    # @return [Array] An array, containing all the reconciler objects, defined in the project
    def reconcilers
      @reconcilers ||= RVGP::Base::Reconciler.all project_path
    end

    # This method will insert all the project tasks, into a Rake object.
    # Typically, 'self' is that object, when calling from a Rakefile. (aka 'main')
    # @param rake_main [Object] The Rake object to attach RVGP to.
    # @return [void]
    def initialize_rake!(rake_main)
      require 'rake/clean'

      CLEAN.include FileList[RVGP.app.config.build_path('*')]

      # This removes clobber from the task list:
      Rake::Task['clobber'].clear_comments

      project_tasks_dir = format('%s/tasks', project_path)
      Rake.add_rakelib project_tasks_dir if File.directory? project_tasks_dir

      RVGP.commands.each do |command_klass|
        command_klass.initialize_rake rake_main if command_klass.respond_to? :initialize_rake
      end

      rake_main.instance_eval do
        default_tasks = %i[reconcile validate_journal validate_system]
        multitask reconcile: RVGP.app.reconcilers.map { |tf| "reconcile:#{tf.as_taskname}" }
        multitask validate_journal: RVGP.app.reconcilers.map { |tf| "validate_journal:#{tf.as_taskname}" }
        multitask validate_system: RVGP.system_validations.task_names

        # There's a chicken-and-an-egg problem that's due:
        #  - users (potentially) wanting to see/trigger specific plot and grid targets, in a clean project
        #  - A pre-requisite that journals (and grids) exist, in order to determine what grid/plot targets
        #    are available.
        # So, what we do here, is do our best to determine what's available in a clean build. And, at the
        # time at which we're ready to start buildings grids/plots - we re-initialize the available tasks
        # based on what was built prior in the running build.
        #
        # Most grids can be determined by examining the reconciler years that exist in the app/ directory.
        # But, in the case that new year starts, and the prior year hasn't been rotated, we'll be adding
        # additional grids here.
        #
        # As for plots... probably we can do a better job of pre-determining those. But, they're pretty
        # inconsequential in the build time, so, unless someone needs this feature for some reason, there
        # are 'no' plots at the time of a full rake build, and the rescan adds them here after the grids
        # are built.

        isnt_reconciled = RVGP::Commands::Reconcile::Target.all.any? { |t| !t.uptodate? }
        if isnt_reconciled
          desc I18n.t('commands.rescan_grids.target_description')
          task :rescan_grids do |_task, _task_args|
            RVGP::Commands::Grid.initialize_rake rake_main
            multitask grid: RVGP.grids.task_names
          end
          default_tasks << :rescan_grids
        end

        default_tasks << :grid
        multitask grid: RVGP.grids.task_names

        if isnt_reconciled || RVGP::Commands::Grid::Target.all.any? { |t| !t.uptodate? }
          # This re-registers the grid tasks, into the rake
          desc I18n.t('commands.rescan_plots.target_description')
          task :rescan_plots do |_task, _task_args|
            RVGP::Commands::Plot.initialize_rake rake_main
            multitask plot: RVGP::Commands::Plot::Target.all.map { |t| "plot:#{t.name}" }
          end
          default_tasks << :rescan_plots
        end

        default_tasks << :plot
        multitask plot: RVGP::Commands::Plot::Target.all.map { |t| "plot:#{t.name}" }

        task default: default_tasks
      end
    end

    # This helper method will create the provided subdir inside the project's build/ directory, if that
    # subdir doesn't already exist. In the case that this subdir already exists, the method terminates
    # gracefully, without action.
    # @return [void]
    def ensure_build_dir!(subdir)
      path = RVGP.app.config.build_path subdir
      FileUtils.mkdir_p path unless File.directory? path
    end

    private

    def require_commands!
      # Built-in commands:
      RVGP::Commands.require_files!

      # App commands:
      require_app_files! 'commands'
    end

    def require_grids!
      require_app_files! 'grids'
    end

    def require_validations!
      # Built-in validations:
      Dir.glob(RVGP::Gem.root('lib/rvgp/validations/*.rb')).sort.each { |file| require file }

      # App validations:
      require_app_files! 'validations'
    end

    def require_app_files!(subdir)
      Dir.glob([project_path, 'app', subdir, '*.rb'].join('/')).sort.each { |file| require file }
    end
  end
end
