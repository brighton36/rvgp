require_relative 'status_output'
require_relative 'config'

module RRA
  class Application
    class InvalidProjectDir < StandardError; end

    attr_reader :project_directory, :logger, :pricer, :config

    def initialize(project_directory)
      raise InvalidProjectDir unless [ project_directory, 
        '%s/app' % project_directory ].all?{ |f| Dir.exist? f }

      @project_directory = project_directory
      @config = RRA::Config.new project_directory
      @logger = StatusOutputRake.new pastel: RRA.pastel

      if File.exist? config.prices_path
        @pricer = RRA::Pricer.new File.read(config.prices_path), 
          # This 'addresses' a pernicious bug that will likely affect you. And
          # I don't have an easy solution, as, I sort of blame ledger for this.
          # The problem will manifest itself in the form of reports that output
          # differently, depending on what reports were built in the process.
          #
          # So, If, say, we're only building 2022 reports. But, a clean build
          # would have built 2021 reports, before instigating the 2022 report 
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
          # the prices.db file. This will ensure consistency in all reports, 
          # regardless of the ranges you run them.
          #
          # If you have a better idea, or some way to ensure consistency in 
          # ledger... PR's welcome!
          before_price_add: lambda{|time, from_alpha, to| 
            puts [
              RRA.pastel.yellow(I18n.t('error.warning')),
              I18n.t('error.missing_entry_in_prices_db', time: time, 
                from: from_alpha, to: to)
            ].join ' '
          } 
      end
    end

    def require_reports!
      require_app_files! 'reports'
    end

    def require_validations!
      Dir.glob('%s/lib/rra/validations/*.rb' % project_directory).each do |file|
        require file
      end
      require_app_files! 'validations'
    end

    def transformers
      @transformers ||= TransformerBase.all project_directory
    end

    def initialize_rake!(rake_main)
      require 'rake/clean'

      RRA::Commands.require_files!
      require_reports!
      require_validations!

      CLEAN.include FileList[RRA.app.config.build_path('*')]

      # This removes clobber from the task list:
      Rake::Task['clobber'].clear_comments

      project_tasks_dir = '%s/tasks' % project_directory
      Rake.add_rakelib project_tasks_dir if File.directory? project_tasks_dir

      RRA.commands.each do |command_klass|
        command_klass.initialize_rake rake_main if command_klass.respond_to? :initialize_rake
      end

      rake_main.instance_eval do 
        multitask transform: RRA.app.transformers.collect{ |transformer|
          'transform:%s' % transformer.as_taskname }
        multitask validate_journal: RRA.app.transformers.collect{ |transformer|
          'validate_journal:%s' % transformer.as_taskname }
        multitask validate_system: RRA.system_validations.task_names
        multitask report: RRA.reports.task_names

        task default: [:transform, :validate_journal, :validate_system, :report]
      end
    end

    def ensure_build_dir!(subdir)
      path = RRA.app.config.build_path subdir
      FileUtils.mkdir_p path unless File.directory? path
    end

    private

    def require_app_files!(subdir)
      Dir.glob('%s/app/%s/*.rb' % [project_directory, subdir]).each do |file|
        require file
      end
    end
  end
end
