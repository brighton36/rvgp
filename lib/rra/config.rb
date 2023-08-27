# frozen_string_literal: true

require_relative 'pta_connection'

module RRA
  # This class provides the app configuration options accessors and parsing logic.
  class Config
    include RRA::PTAConnection::AvailabilityHelper

    attr_reader :prices_path, :project_journal_path

    def initialize(project_path)
      @project_path = project_path
      @build_path = format('%s/build', project_path)

      config_path = project_path 'config/rra.yml'
      @yaml = RRA::Yaml.new config_path, project_path if File.exist? config_path

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

      # I'm not crazy about this default.. Mabe we should raise an error if
      # this value isn't set...
      @grid_starting_at = @yaml[:grid_starting_at] if @yaml.key? :grid_starting_at
      @grid_starting_at ||= default_grid_starting_at

      # NOTE: RRA::Ledger.newest_transaction.date.year works in lieu of Date.today,
      #       but that query takes forever. (and it requires that we've already
      #       performed a build step at the time it's called) so, we use
      #       Date.today instead.
      @grid_ending_at = @yaml[:grid_ending_at] if @yaml.key? :grid_ending_at
      @grid_ending_at ||= default_grid_ending_at
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

    def default_grid_starting_at
      transformer_years = Dir.glob(project_path('app/transformers/*.yml')).map do |f|
        ::Regexp.last_match(1).to_i if /\A(\d{4}).+/.match File.basename(f)
      end.compact.uniq.sort

      transformer_years.empty? ? (Date.today << 12) : Date.new(transformer_years.first, 1, 1)
    end

    # We want/need grid tasks that are defined by (year)-gridname. However, we want
    # an exact end date, that's based off the output of the build step.
    #
    # So, what we do, is check for the prescence of journal files, and if they're
    # not there, we just return the end of the current year.
    #
    # If we find the journal files, we return the last 'full month' of data
    #
    # NOTE: we probably could/should cache the newest_transaction_date, but,
    # that would be a PITA right now
    def default_grid_ending_at
      # It's important that we return a lambda, so that the call_or_return()
      # re-runs this code after the grids are generated
      lambda do
        return Date.today unless Dir[build_path('journals/*.journal')].count.positive?

        end_date = pta_adapter.newest_transaction_date file: project_journal_path

        return end_date if end_date == Date.civil(end_date.year, end_date.month, -1)

        if end_date.month == 1
          Date.civil end_date.year - 1, 12, 31
        else
          Date.civil end_date.year, end_date.month - 1, -1
        end
      end
    end

    def call_or_return_date(value)
      ret = value.respond_to?(:call) ? value.call : value
      ret.is_a?(Date) ? ret : Date.strptime(ret)
    end
  end
end
