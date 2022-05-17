require 'rra/plot'

class RRA::Commands::Plot < RRA::CommandBase
  accepts_options OPTION_ALL, OPTION_LIST, [:stdout, :s], [:interactive, :i]

  class Target < RRA::CommandBase::PlotTarget

    def execute(options)
      if options[:stdout]
        puts @transformer.to_ledger
      else
        @transformer.to_ledger!
      end

      return nil
    end

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
