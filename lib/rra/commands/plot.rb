require 'rra/plot'

class RRA::Commands::Plot < RRA::CommandBase
  accepts_options OPTION_ALL, OPTION_LIST, [:stdout, :s], [:interactive, :i]

  include RakeTask
  rake_tasks :plot

  def execute!
    RRA.app.ensure_build_dir! 'plots' unless options[:stdout]
    super
  end

  # TODO: This should get broken down, if possible. We should only use this
  # path, if there are no available reports
  def self.initialize_rake(rake_main)
    command_klass = self

    # TODO: This was copy pasta'd from RakeTask
    rake_main.instance_eval do
      desc "Generate all Plots"
      task "plot" do |task, task_args|
        Target.all.each do |target|
          command_klass.task_exec(target).call(task, task_args)
        end
      end
    end

  end

  class Target < RRA::CommandBase::PlotTarget
    def execute(options)
      if options[:stdout]
        puts plot.script(name)
      else
        RRA.app.ensure_build_dir! 'plots'
        plot.write!(name)
      end

      if options[:interactive]
        # TODO: Display a window
      end

      return nil
    end
  end

end
