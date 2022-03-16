class RRA::Commands::ValidateJournal < RRA::CommandBase
  accepts_options OPTION_ALL, OPTION_LIST

  include RakeTask
  rake_tasks :validate_journal

  class Target < RRA::CommandBase::TransformerTarget
    for_command :validate_journal

    def uptodate?
      @transformer.validated?
    end

    def mark_validated!
      @transformer.mark_validated!
    end

    def execute(options)
      disable_checks = @transformer.disable_checks.collect(&:to_sym)

      # Make sure the file exists, before proceeding with anything:
      return [I18n.t('commands.transform.errors.journal_missing')], 
        [] unless File.exist? @transformer.output_file

      warnings, errors = [], []

      RRA.journal_validations.classes.each do |klass|
        unless disable_checks.include? klass.name.to_sym
          validation = klass.new @transformer
          unless validation.is_valid?
            warnings += validation.warnings
            errors += validation.errors
          end
        end
      end

      @transformer.mark_validated! if errors.length + warnings.length == 0

      [warnings, errors]
    end
  end
end
