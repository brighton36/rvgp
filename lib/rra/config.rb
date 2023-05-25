# frozen_string_literal: true

module RRA
  # This class provides the app configuration options accessors and parsing logic.
  class Config
    attr_reader :prices_path, :project_journal_path

    def initialize(project_path)
      @project_path = project_path
      @build_path = format('%s/build', project_path)

      config_path = project_path 'config/rra.yml'
      @yaml = RRA::Yaml.new config_path, project_path if File.exist? config_path

      # I'm not crazy about this default.. Mabe we should raise an error if
      # this value isn't set...
      @grid_starting_at = @yaml.key?(:grid_starting_at) ? @yaml[:grid_starting_at] : (Date.today - 365)

      # NOTE: RRA::Ledger.newest_transaction.date.year works in lieu of Date.today,
      #       but that query takes forever. (and it requires that we've already
      #       performed a build step at the time it's called) so, we use
      #       Date.today instead.
      @grid_ending_at = @yaml.key?(:grid_ending_at) ? @yaml[:grid_ending_at] : Date.today

      @prices_path = @yaml.key?(:prices_path) ? @yaml[:prices_path] : project_path('journals/prices.db')

      if @yaml.key?(:project_journal_path)
        @project_journal_path = project_path @yaml[:project_journal_path]
      else
        journals_in_project_path = Dir.glob format('%s/*.journal', @project_path)
        if journals_in_project_path.length != 1
          raise StandardError,
                format(
                  'Unable to automatically determine the project journal. Probably you want one of these ' \
                  'files: %<files>s. Set the project_journal_path parameter in ' \
                  'your config file, to the relative pathname, of the project journal.',
                  files: journals_in_project_path.join(', ')
                )
        end
        @project_journal_path = journals_in_project_path.first
      end
    end


    def [](attr)
      @yaml[attr]
    end

    def key?(attr)
      @yaml.key? attr
    end

    def grid_starting_at
      call_or_return_date @grid_starting_at
    end

    def grid_ending_at
      call_or_return_date @grid_ending_at
    end

    def grid_years
      grid_starting_at.year.upto(grid_ending_at.year)
    end

    def project_path(subdirectory = nil)
      subdirectory ? [@project_path, subdirectory].join('/') : @project_path
    end

    def build_path(subdirectory = nil)
      subdirectory ? [@build_path, subdirectory].join('/') : @build_path
    end

    private

    def call_or_return_date(value)
      ret = value.respond_to?(:call) ? value.call : value
      ret.is_a?(Date) ? ret : Date.strptime(ret)
    end
  end
end
