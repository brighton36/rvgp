
module RRA
  class Config
    attr_reader :build_path, :prices_path, :report_starting_year, 
      :report_ending_year

    def initialize(project_path)
      @project_path = project_path
      @build_path = '%s/build' % project_path

      @yaml = (File.exist?(project_path('config/rra.yml'))) ? 
        RRA::Yaml.new(project_path('config/rra.yml')) : nil

      # I'm not crazy about this default.. Mabe we should raise an error if 
      # this value isn't set...
      @report_starting_year = @yaml.has_key?(:report_starting_year) ? 
        @yaml[:report_starting_year] : (Date.today.year-1)

      # NOTE: RRA::Ledger.newest_transaction.date.year works in lieu of Date.today, 
      #       but that query takes forever. (and it requires that we've already 
      #       performed a build step at the time it's called) so, we use 
      #       Date.today instead.
      @report_ending_year = @yaml.has_key?(:report_ending_year) ? 
        @yaml[:report_ending_year] : Date.today.year

      @prices_path = @yaml.has_key?(:prices_path) ? 
        @yaml[:prices_path] : project_path('journals/prices.db')
    end

    def [](attr); @yaml[attr]; end
    def has_key?(attr); @yaml.has_key? attr; end

    def report_years
      report_starting_year.upto(report_ending_year)
    end

    def project_path(subdirectory = nil)
      (subdirectory)? [@project_path,subdirectory].join('/') : @project_path
    end

    def build_path(subdirectory = nil)
      (subdirectory)? [@build_path,subdirectory].join('/') : @build_path
    end

    def method_missing(name)
      # TODO: I'd like to see this hook into a class accessor maybe, with 
      # additional lambda's...
      super(name)
    end
  end
end
