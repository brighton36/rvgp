class RRA::Commands::Report < RRA::CommandBase
  accepts_options OPTION_ALL, OPTION_LIST

  include RakeTask
  rake_tasks :report

  def execute!(&block)
    RRA.app.ensure_build_dir! 'reports'
    super(&block)
  end

  class Target < RRA::CommandBase::TargetBase
    def initialize(report_klass, year)
      @report_klass, @year, @name, @status_name  = report_klass, 
        year.to_i, [year,report_klass.name.tr('_', '-')].join('-'), 
        report_klass.status_name(year) 
    end

    def description
      I18n.t 'commands.report.target_description', 
        description: @report_klass.description, year: @year
    end

    def uptodate?
      @report_klass.uptodate? @year
    end

    def execute(options)
      @report_klass.new(@year).to_file! 
    end

    def self.all
      RRA.app.config.report_years.collect{|year|
        RRA.reports.classes.collect{|klass| self.new klass, year }
      }.flatten
    end
  end
end
