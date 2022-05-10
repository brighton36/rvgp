
module RRA
  class Config
    attr_reader :build_path, :prices_path

    def initialize(project_path)
      @project_path = project_path
      @build_path = '%s/build' % project_path

      @yaml = (File.exist?(project_path('config/rra.yml'))) ? 
        RRA::Yaml.new(project_path('config/rra.yml'), project_path) : nil

      # I'm not crazy about this default.. Mabe we should raise an error if 
      # this value isn't set...
      @report_starting_at = @yaml.has_key?(:report_starting_at) ?
        @yaml[:report_starting_at] : (Date.today-365)

      # NOTE: RRA::Ledger.newest_transaction.date.year works in lieu of Date.today, 
      #       but that query takes forever. (and it requires that we've already 
      #       performed a build step at the time it's called) so, we use 
      #       Date.today instead.
      @report_ending_at = @yaml.has_key?(:report_ending_at) ?
        @yaml[:report_ending_at] : Date.today.year

      @prices_path = @yaml.has_key?(:prices_path) ? 
        @yaml[:prices_path] : project_path('journals/prices.db')
    end

    def [](attr); @yaml[attr]; end
    def has_key?(attr); @yaml.has_key? attr; end

    def report_starting_at
      call_or_return_date @report_starting_at
    end

    def report_ending_at
      call_or_return_date @report_ending_at
    end

    def report_years
      report_starting_at.year.upto(report_ending_at.year)
    end

    def project_path(subdirectory = nil)
      (subdirectory)? [@project_path,subdirectory].join('/') : @project_path
    end

    def build_path(subdirectory = nil)
      (subdirectory)? [@build_path,subdirectory].join('/') : @build_path
    end

    private

    def call_or_return_date(value)
      ret = value.respond_to?(:call) ? value.call : value
      (ret.kind_of? Date) ? ret : Date.strptime(ret)
    end

  end
end
