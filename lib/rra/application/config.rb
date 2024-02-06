# frozen_string_literal: true

require_relative '../pta'

module RRA
  class Application
    # This class provides the app configuration options accessors and parsing logic.
    class Config
      include RRA::Pta::AvailabilityHelper
      attr_reader :prices_path, :project_journal_path

      # Given the provided project path, this object will parse and store the
      # config/rra.yaml, as well as provide default values for otherwise unspecified attributes
      # in this file.
      # @param project_path [String] The path, to an RRA project directory.
      def initialize(project_path)
        @project_path = project_path
        @build_path = format('%s/build', project_path)

        config_path = project_path 'config/rra.yml'
        @yaml = RRA::Utilities::Yaml.new config_path, project_path if File.exist? config_path

        RRA::Pta.pta_adapter = @yaml[:pta_adapter].to_sym if @yaml.key? :pta_adapter

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

        # NOTE: pta_adapter.newest_transaction_date.year works in lieu of Date.today,
        #       but that query takes time. (and it requires that we've already
        #       performed a build step at the time it's called) so, we use
        #       Date.today instead.
        @grid_ending_at = @yaml[:grid_ending_at] if @yaml.key? :grid_ending_at
        @grid_ending_at ||= default_grid_ending_at
      end

      # Return the contents of the provided attr, from the project's config/rra.yaml
      # @return [Object] the value corresponding to the provided attr
      def [](attr)
        @yaml[attr]
      end

      # Returns a boolean indicating whether a value for the provided attr was specified in the project's
      # config/rra.yaml
      # @return [TrueClass, FalseClass] whether the key was specified
      def key?(attr)
        @yaml.key? attr
      end

      # Returns the starting date, for all grids that will be generated in this project.
      # @return [Date] when to commence grid building
      def grid_starting_at
        call_or_return_date @grid_starting_at
      end

      # Returns the ending date, for all grids that will be generated in this project.
      # @return [Date] when to finish grid building
      def grid_ending_at
        call_or_return_date @grid_ending_at
      end

      # The years, for which we will be building grids
      # @return [Array<Integer>] What years to expect in our build/grids directory (and their downstream targets)
      def grid_years
        grid_starting_at.year.upto(grid_ending_at.year)
      end

      # Returns the full path, to a file or directory, in the project. If no relpath was provided, this
      # method returns the full path to the project directory.
      # @param relpath [optional, String] The relative path, to a filesystem object in the current project
      # @return [String] The full path to the requested resource
      def project_path(relpath = nil)
        relpath ? [@project_path, relpath].join('/') : @project_path
      end

      # Returns the full path, to a file or directory, in the project's build/ directory. If no relpath was provided,
      # this method returns the full path to the project build directory.
      # @param relpath [optional, String] The relative path, to a filesystem object in the current project
      # @return [String] The full path to the requested resource
      def build_path(relpath = nil)
        relpath ? [@build_path, relpath].join('/') : @build_path
      end

      # This is a bit of a kludge. We wanted this in a few places, so, I DRY'd it here. tldr: this returns an array
      # of years (as integers), which, were groked from the file names found in the app/transformers directory.
      # It's a rough shorthand, that, ends up being a better 'guess' of start/end dates, than Date.today
      # @!visibility private
      def transformer_years
        Dir.glob(project_path('app/transformers/*.yml')).map do |f|
          ::Regexp.last_match(1).to_i if /\A(\d{4}).+/.match File.basename(f)
        end.compact.uniq.sort
      end

      private

      def default_grid_starting_at
        years = transformer_years
        years.empty? ? (Date.today << 12) : Date.new(years.first, 1, 1)
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
        # TODO: This lambda is goofy. Let's see if we can nix it
        lambda do
          unless Dir[build_path('journals/*.journal')].count.positive?
            years = transformer_years
            return years.empty? ? Date.today : Date.new(years.last, 12, 31)
          end

          # TODO: I think this is why our rake / rake clean output is mismatching atm
          end_date = pta.newest_transaction_date file: project_journal_path

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
end
