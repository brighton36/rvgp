class RRA::Commands::Report < RRA::CommandBase
  accepts_options OPTION_ALL, OPTION_LIST

  include RakeTask
  rake_tasks :report

  def execute!(&block)
    RRA.app.ensure_build_dir! 'reports'
    super(&block)
  end

  class Target < RRA::CommandBase::TargetBase
    def initialize(report_klass, starting_at, ending_at)
      @starting_at, @ending_at = starting_at, ending_at
      @report_klass, @name, @status_name = report_klass,
        [year,report_klass.name.tr('_', '-')].join('-'),
        report_klass.status_name(year)
    end

    def description
      I18n.t 'commands.report.target_description', 
        description: @report_klass.description, year: year
    end

    def uptodate?
      @report_klass.uptodate? year
    end

    def execute(options)
      # RRA.app.config.report_years
      @report_klass.new(@starting_at, @ending_at).to_file!
    end

    def self.all
      starting_at = RRA.app.config.report_starting_at
      ending_at = RRA.app.config.report_ending_at

      starting_at.year.upto(ending_at.year).collect{ |y|
        RRA.reports.classes.collect do |klass|
          self.new klass,
            ((y == starting_at.year) ? starting_at : Date.new(y, 1,1)),
            ((y == ending_at.year) ? ending_at : Date.new(y, 12, 31))
        end
      }.flatten
    end

    private

    def year
      @starting_at.year
    end

  end
end
