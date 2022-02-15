class RRA::Commands::ValidateSystem < RRA::CommandBase
  accepts_options OPTION_ALL, OPTION_LIST

  include RakeTask
  rake_tasks :validate_system

  class Target < RRA::CommandBase::TargetBase
    def initialize(validation_klass)
      @validation_klass, @name, @status_name, @description = validation_klass,
        validation_klass.name, validation_klass.status_label,
        validation_klass.description
    end

    def uptodate?
      @validation_klass.validated?
    end

    def execute(options)
      validation = @validation_klass.new
      validation.mark_validated! if validation.is_valid?
      [validation.warnings, validation.errors]
    end

    def self.all
      RRA.system_validations.collect{|klass| self.new klass}
    end
  end

end
