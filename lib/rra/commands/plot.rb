# frozen_string_literal: true

require_relative '../plot'

module RRA
  module Commands
    # @!visibility private
    # This class contains the handling of the 'plot' command and task.
    class Plot < RRA::Base::Command
      accepts_options OPTION_ALL, OPTION_LIST, %i[stdout s]

      include RakeTask
      rake_tasks :plot

      # @!visibility private
      def execute!
        RRA.app.ensure_build_dir! 'plots' unless options[:stdout]
        super
      end

      # TODO: This should get broken down, if possible. We should only use this
      # path, if there are no available grids
      # @!visibility private
      def self.initialize_rake(rake_main)
        command_klass = self

        # TODO: This was copy pasta'd from RakeTask
        # TODO: This should show each plot individually, if the grids exist...
        rake_main.instance_eval do
          desc 'Generate all Plots'
          task 'plot' do |task, task_args|
            Target.all.each { |target| command_klass.task_exec(target).call task, task_args }
          end
        end
      end

      # This class represents a plot, available for building. And dispatches a build request.
      # Typically, the name of a plot takes the form of "#\\{year}-#\\{plotname}". See
      # RRA::Base::Command::PlotTarget, from which this class inherits, for a better
      # representation of how this class works.
      # @!visibility private
      class Target < RRA::Base::Command::PlotTarget
        # @!visibility private
        def execute(options)
          if options[:stdout]
            puts plot.script(name)
          else
            RRA.app.ensure_build_dir! 'plots'
            plot.write!(name)
          end

          nil
        end
      end
    end
  end
end
