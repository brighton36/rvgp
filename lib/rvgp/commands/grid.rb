# frozen_string_literal: true

module RVGP
  module Commands
    # @!visibility private
    # This class contains the handling of the 'grid' command and task. This
    # code provides the list of grids that are available in the application, and
    # dispatches requests to build these grids.
    class Grid < RVGP::Base::Command
      accepts_options OPTION_ALL, OPTION_LIST

      include RakeTask
      rake_tasks :grid

      # @!visibility private
      def execute!(&block)
        RVGP.app.ensure_build_dir! 'grids'
        super(&block)
      end

      # @!visibility private
      # This class represents a grid, available for building. In addition, the #.all
      # method, returns the list of available targets.
      class Target < RVGP::Base::Command::Target
        attr_reader :grid

        # @!visibility private
        def initialize(grid)
          @grid = grid
          super grid.label, grid.status_name
        end

        # @!visibility private
        def description
          grid.status_name
        end

        # @!visibility private
        def uptodate?
          grid.uptodate?
        end

        # @!visibility private
        def execute(_options)
          grid.to_file!
        end

        # @!visibility private
        def self.all
          RVGP.grids.instances.flatten.map { |instance| new instance }
        end
      end
    end
  end
end
