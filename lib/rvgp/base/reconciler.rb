# frozen_string_literal: true

require_relative '../utilities'

module RVGP
  module Base
    # TODO: Document this new, large feature
    # @attr_reader [String] label The contents of the yaml :label parameter (see above)
    # @attr_reader [String] file The full path to the reconciler yaml file this class was parsed from
    # @attr_reader [String] input_file The contents of the yaml :input parameter (see above)
    # @attr_reader [String] output_file The contents of the yaml :output parameter (see above)
    # @attr_reader [Array<String>] disable_checks The JournalValidations that are disabled on this reconciler (see
    #                                             above)
    class Reconciler
      include RVGP::Utilities

      # @!visibility private
      # This class exists as an intermediary class, mostly to support the source
      # formats of both .csv and .journal files, without forcing one conform to the
      # other.
      class Posting
        attr_accessor :line_number, :date, :effective_date, :description, :commodity, :complex_commodity, :from, :to,
                      :tags, :targets

        def initialize(line_number, opts = {})
          @line_number = line_number
          @date = opts[:date]
          @effective_date = opts[:effective_date]
          @description = opts[:description]
          @commodity = opts[:commodity]
          @complex_commodity = opts[:complex_commodity]
          @from = opts[:from]
          @to = opts[:to]
          @tags = opts[:tags] || []
          @targets = opts[:targets] || []
        end

        # @!visibility private
        def to_journal_posting
          transfers = targets.map do |target|
            RVGP::Journal::Posting::Transfer.new target[:to],
                                                 effective_date: target[:effective_date],
                                                 commodity: target[:commodity],
                                                 complex_commodity: target[:complex_commodity],
                                                 tags: target[:tags]&.map(&:to_tag)
          end

          RVGP::Journal::Posting.new date,
                                     description,
                                     tags: tags&.map(&:to_tag),
                                     transfers: transfers + [RVGP::Journal::Posting::Transfer.new(from)]
        end
      end

      REQUIRED_ATTRS = %i[label file output_file input_file]
      attr_reader(*REQUIRED_ATTRS, :disable_checks)

      # @!visibility private
      HEADER = ";;; %s --- Description -*- mode: ledger; -*-\n; vim: syntax=ledger"

      # Create a Reconciler
      def initialize(from_file)
        @file ||= from_file
        @disable_checks ||= []
        @dependencies ||= []
        missing_attrs = REQUIRED_ATTRS.select { |attr| send(attr).nil? }

        unless missing_attrs.empty?
          raise StandardError, format('Missing required attributes %s', missing_attrs.join(','))
        end
      end

      # Returns the taskname to use by rake, for this reconciler
      # @return [String] The taskname, based off the :file basename
      def as_taskname
        File.basename(file, File.extname(file)).tr('^a-z0-9', '-')
      end

      # @!visibility private
      # This is kinda weird I guess, but, we use it to identify whether the
      # provided str matches one of the unique fields that identifying this object
      # this is mostly (only?) used by the command objects, to resolve parameters
      def matches_argument?(str)
        str_as_file = File.expand_path str

        as_taskname == str ||
          label == str ||
          file == str_as_file ||
          input_file == str_as_file ||
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

      # @!visibility private
      def reconcile_posting(rule, posting)
        # NOTE: The shorthand(s) produce more than one tx per csv line, sometimes:

        posting.from = rule[:from] if rule.key? :from

        posting.tags << rule[:tag] if rule.key? :tag

        # Let's do a find and replace on the :to if we have anything captured
        # This is kind of rudimentary, and only supports named_caputers atm
        # but I think it's fine for now. Probably it's broken wrt cash back or
        # something...
        rule_to = rule[:to].dup
        if rule[:captures]
          rule_to.scan(/\$([0-9a-z]+)/i).each do |substitutes|
            substitutes.each do |substitute|
              replace = rule[:captures][substitute]
              rule_to = rule_to.sub format('$%s', substitute), replace if replace
            end
          end
        end

        if rule.key? :to_shorthand
          rule_key = posting.commodity.positive? ? :expense : :income

          @shorthand ||= {}
          @shorthand[rule_key] ||= {}
          mod = @shorthand[rule_key][rule[:index]]

          unless mod
            shorthand_klass = format 'RVGP::Reconcilers::Shorthand::%s', rule[:to_shorthand]

            unless Object.const_defined?(shorthand_klass)
              raise StandardError, format('Unknown shorthand %s', shorthand_klass)
            end

            mod = Object.const_get(shorthand_klass).new rule

            @shorthand[rule_key][rule[:index]] = mod
          end

          # TODO: Dry this out with the above rule[:captures]? This got a little ridiculous... maybe
          # just do this at the end of the function?
          shorthand_ret = mod.to_tx posting
          if rule[:captures]
            [shorthand_ret].flatten.each do |posting|
              posting.targets.each do |target|
                target[:to].scan(/\$([0-9a-z]+)/i).each do |substitutes|
                  substitutes.each do |substitute|
                    replace = rule[:captures][substitute]
                    target[:to] = target[:to].sub format('$%s', substitute), replace if replace
                  end
                end
              end
            end
          end

          shorthand_ret

        elsif rule.key?(:targets)
          # NOTE: I guess we don't support cashback when multiple targets are
          # specified ATM

          # If it turns out we need this feature in the future, I guess,
          # implement it?
          raise StandardError, 'Unimplemented.' if cash_back&.match(posting.description)

          posting.targets = rule[:targets].map do |rule_target|
            if rule_target.key? :currency
              commodity = RVGP::Journal::Commodity.from_symbol_and_amount(
                rule_target[:currency] || default_currency,
                rule_target[:amount].to_s
              )
            elsif rule_target.key? :complex_commodity
              complex_commodity = RVGP::Journal::ComplexCommodity.from_s(rule_target[:complex_commodity])
            else
              commodity = rule_target[:amount].to_s.to_commodity
            end

            { to: rule_target[:to],
              commodity: commodity,
              complex_commodity: complex_commodity,
              tags: rule_target[:tags] }
          end

          posting
        else
          # We unroll some of the allocation in here, since (I think) the logic
          # relating to cash backs and such are in 'the bank' and not 'the transaction'
          residual_commodity = posting.commodity

          if cash_back&.match(posting.description)
            cash_back_commodity = RVGP::Journal::Commodity.from_symbol_and_amount(
              ::Regexp.last_match(1), Regexp.last_match(2)
            )
            residual_commodity -= cash_back_commodity
            posting.targets << { to: cash_back_to, commodity: cash_back_commodity }
          end

          posting.targets << {
            effective_date: posting.effective_date,
            to: rule_to,
            commodity: residual_commodity,
            tags: rule[:to_tag] ? [rule[:to_tag]] : nil
          }

          posting
        end
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
      # @return [Array<RVGP::Reconcilers::CsvReconciler, RVGP::Reconcilers::JournalReconciler>]
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
            YamlReconciler
          else # .rb
            require fullpath
            begin
              klass_name = string_to_classname(File.basename(filename, '.rb'))
              const_get klass_name
            rescue NameError
              raise StandardError, "Missing #{klass_name} class in #{fullpath}"
            end
          end.all(fullpath)
        end.flatten
      end

      # @!visibility private
      def self.string_to_classname(str)
        str.split(/[^a-zA-Z0-9]/).map(&:capitalize).join.to_sym
      end
    end
  end
end
