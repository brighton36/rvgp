# frozen_string_literal: true

require_relative '../utilities'

module RVGP
  module Base
    # @attr_reader [String] label The contents of the yaml :label parameter (see above)
    # @attr_reader [String] file The full path to the reconciler yaml file this class was parsed from
    # @attr_reader [String] input_file The contents of the yaml :input parameter (see above)
    # @attr_reader [String] output_file The contents of the yaml :output parameter (see above)
    # @attr_reader [String] taskname The taskname to use by rake, for this reconciler. Defaults to
    # @attr_reader [Hash] input_options These are (usually shared) formatting directives to use in the
    # transformation of the input file, into the intermediate format used to construct a posting
    # @attr_reader [Hash<String, String>] balances A hash of dates (in 'YYYY-MM-DD') to commodities (as string)
    # corresponding to the balance that are expected on those dates. See
    # {RVGP::Validations::BalanceValidation} for details on this feature.
    # @attr_reader [Array<String>] disable_checks The JournalValidations that are disabled on this reconciler (see
    # above)
    class Reconciler
      include RVGP::Utilities

      REQUIRED_ATTRS = %i[taskname label file output_file input_file]
      attr_reader(*REQUIRED_ATTRS, :disable_checks, :input_options, :balances)

      # @!visibility private
      HEADER = ";;; %s --- Description -*- mode: ledger; -*-\n; vim: syntax=ledger"

      # Create a Reconciler
      def initialize(file:, label: nil, disable_checks: nil, dependencies: nil, taskname: nil,
                     input_file: nil, input_options: nil, output_file: nil, balances: nil)
        @file = file
        @disable_checks = disable_checks || []
        @dependencies = dependencies || []
        @input_options = input_options

        @taskname = if taskname
                      taskname
                    elsif input_file
                      File.basename(input_file, File.extname(input_file))
                    else
                      File.basename(file, File.extname(file)).tr('^a-z0-9', '-')
                    end

        @label = label || @taskname
        @input_file ||= input_file || RVGP.app.config.project_path(format('feeds/%s.csv', @taskname))
        @output_file ||= output_file || RVGP.app.config.build_path(format('journals/%s.journal', @taskname))
        missing_attrs = REQUIRED_ATTRS.select { |attr| send(attr).nil? }

        unless missing_attrs.empty?
          raise StandardError, format('Missing required attributes %s', missing_attrs.join(', '))
        end

        @balances = balances
      end

      # @!visibility private
      # This is kinda weird I guess, but, we use it to identify whether the
      # provided str matches one of the unique fields that identifying this object
      # this is mostly (only?) used by the command objects, to resolve parameters
      def matches_argument?(str)
        str_as_file = File.expand_path str

        taskname == str || label == str || file == str_as_file || input_file == str_as_file ||
          output_file == str_as_file
      end

      # Returns the file paths that were referenced by this reconciler in one form or another.
      # Useful for determining build freshness.
      # @return [Array<String>] dependent files, in this reconciler.
      def dependencies
        [file, input_file] + @dependencies
      end

      # @!visibility private
      def uptodate?
        FileUtils.uptodate? output_file, dependencies
      end

      # @!visibility private
      # This file is used to mtime the last success
      def validated_touch_file_path
        format('%s.valid', output_file)
      end

      # @!visibility private
      def mark_validated!
        FileUtils.touch validated_touch_file_path
      end

      # @!visibility private
      def validated?
        FileUtils.uptodate? validated_touch_file_path, [output_file]
      end

      # @!visibility private
      def transform_commodity(from)
        # NOTE: We could be dealing with a ComplexCommodity, hence the check
        # for a .code
        if from.respond_to?(:code) && @transform_commodities.key?(from.code.to_sym)
          # NOTE: Maybe we need to Create a new Journal::Commodity, so that the
          # alphacode reloads?
          from.code = @transform_commodities[from.code.to_sym]
        end

        from
      end

      # Builds the contents of this reconcilere's output file, and returns it. This is the finished
      # product of this class
      # @return [String] a PTA journal, composed of the input_file's transactions, after all rules are applied.
      def to_ledger
        [HEADER % label, postings.map(&:to_ledger), ''].flatten.join("\n\n")
      end

      # Writes the contents of #to_ledger, to the :output_file 
      # @return [void]
      def to_ledger!
        File.write output_file, to_ledger
        RVGP::CachedPta.invalidate! output_file
      end

      # Returns an array of all of the reconcilers found in the specified path.
      # @param [String] directory_path The path containing your yml reconciler files
      # @return [Array<RVGP::Base::Reconciler]
      #   An array of parsed reconcilers.
      def self.all(directory_path)
        # NOTE: I'm not crazy about this method. Probably we should have
        # implemented a single Reconciler class, with CSV/Journal drivers.
        # Nonetheless, this code works for now. Maybe if we add another
        # driver, we can renovate it, and add some kind of registry for drivers.

        base = format('%s/app/reconcilers', directory_path)
        Dir.glob(['*.yml', '*.rb'], base:).map do |filename|
          fullpath = [base, filename].join('/')

          # We could probably make this a registry, though, I'd like to support
          # web addresses eventually. So, probably this design pattern would
          # have to just be reconsidered entirely around that time.
          if File.extname(filename).downcase == '.yml'
            RVGP::Reconcilers::YamlReconciler
          else # .rb
            require fullpath
            begin
              klass_name = string_to_classname(File.basename(filename, '.rb'))
              const_get klass_name
            rescue NameError
              raise StandardError, "Missing #{klass_name} class in #{fullpath}"
            end
          end.all(file: fullpath)
        end.flatten
      end

      def self.map_feeds(glob = '*.csv', &block)
        base = RVGP.app.config.project_path('feeds')
        Dir.glob("**/#{glob}", base:).map { |f| block.call([base, f].join('/')) }
      end

      # @!visibility private
      def self.string_to_classname(str)
        str.split(/[^a-zA-Z0-9]/).map(&:capitalize).join.to_sym
      end
    end
  end
end
