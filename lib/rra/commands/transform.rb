class RRA::Commands::Transform < RRA::CommandBase
  accepts_options OPTION_ALL, OPTION_LIST, [:stdout, :s] 

  include RakeTask
  rake_tasks :transform

  def execute!
    RRA.app.ensure_build_dir! 'journals' unless options[:stdout]
    (options[:stdout]) ? execute_each_target : super
  end

  class Target < RRA::CommandBase::TransformerTarget
    for_command :validate_journal

    def description
      I18n.t 'commands.transform.target_description', 
        input_file: @transformer.input_file
    end

    def uptodate?; 
      @transformer.uptodate?
    end

    def execute(options)
      if options[:stdout]
        puts @transformer.to_ledger
      else
        @transformer.to_ledger!
      end

      return nil
    end
  end

end
