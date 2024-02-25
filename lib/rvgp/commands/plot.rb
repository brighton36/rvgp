# frozen_string_literal: true

require_relative '../plot'

module RVGP
  module Commands
    # @!visibility private
    # This class contains the handling of the 'plot' command and task.
    class Plot < RVGP::Base::Command
      accepts_options OPTION_ALL, OPTION_LIST, %i[stdout s]

      include RakeTask
      rake_tasks :plot

      # @!visibility private
      def execute!
        RVGP.app.ensure_build_dir! 'plots' unless options[:stdout]
        super
      end

      # This class represents a plot, available for building. And dispatches a build request.
      # Typically, the name of a plot takes the form of "#\\{year}-#\\{plotname}". See
      # RVGP::Base::Command::PlotTarget, from which this class inherits, for a better
      # representation of how this class works.
      # @!visibility private
      class Target < RVGP::Base::Command::PlotTarget
        # @!visibility private
        def execute(options)
          if options[:stdout]
            puts plot.script(name)
          else
            RVGP.app.ensure_build_dir! 'plots'
            plot.write!(name)
          end

          nil
        end
      end
    end
  end
end
