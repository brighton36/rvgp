# frozen_string_literal: true

module RRA
  module Commands
    # @!visibility private
    # This class contains dispatch logic for the 'validate_system' command and task.
    class ValidateSystem < RRA::Base::Command
      accepts_options OPTION_ALL, OPTION_LIST

      include RakeTask
      rake_tasks :validate_system

      # @!visibility private
      # This class principally represents the system validations, that are defined
      # in the application directory. Unlike the journal validations, these
      # targets are not specific to years, or reconcilers.
      class Target < RRA::Base::Command::Target
        # @!visibility private
        def initialize(validation_klass)
          @validation_klass = validation_klass
          @description = validation_klass.description
          super validation_klass.name, validation_klass.status_label
        end

        # @!visibility private
        def uptodate?
          @validation_klass.validated?
        end

        # @!visibility private
        def execute(_options)
          validation = @validation_klass.new
          validation.mark_validated! if validation.valid?
          [validation.warnings, validation.errors]
        end

        # @!visibility private
        def self.all
          RRA.system_validations.collect { |klass| new klass }
        end
      end
    end
  end
end
