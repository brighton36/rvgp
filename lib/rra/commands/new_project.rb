# frozen_string_literal: true

module RRA
  module Commands
    # This class handles the request to create a new RRA project.
    class NewProject < RRA::CommandBase
      def initialize(*args)
        @app_dir = args.first
        puts args.inspect
      end

      def valid?
        # TODO: We need to check to see if the directory parameter was even provided
        true
      end

      def execute!
        # TODO: Check if the directory exists
        puts "inside the execute"
        # TODO
      end
    end
  end
end
