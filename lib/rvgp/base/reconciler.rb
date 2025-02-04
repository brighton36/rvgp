# frozen_string_literal: true

require_relative '../utilities'

module RVGP
  module Base
    # See {RVGP::Reconcilers} for extensive detail on the structure and function of reconciler yaml files, and
    # reconciler functionality.
    #
    # @attr_reader [String] label The contents of the yaml :label parameter (see above)
    # @attr_reader [String] file The full path to the reconciler yaml file this class was parsed from
    # @attr_reader [String] output_file The contents of the yaml :output parameter (see above)
    # @attr_reader [String] input_file The contents of the yaml :input parameter (see above)
    # @attr_reader [Date] starts_on The contents of the yaml :starts_on parameter (see above)
    # @attr_reader [Hash<String, String>] balances A hash of dates (in 'YYYY-MM-DD') to commodities (as string)
    #                                              corresponding to the balance that are expected on those dates.
    #                                              See {RVGP::Validations::BalanceValidation} for details on this
    #                                              feature.
    # @attr_reader [Array<String>] disable_checks The JournalValidations that are disabled on this reconciler (see
    #                                             above)
    # @attr_reader [String] from The contents of the yaml :from parameter (see above)
    # @attr_reader [Array<Hash>] income_rules The contents of the yaml :income_rules parameter (see above)
    # @attr_reader [Array<Hash>] expense_rules The contents of the yaml :expense_rules parameter (see above)
    # @attr_reader [Array<Hash>] tag_accounts The contents of the yaml :tag_accounts parameter (see above)
    # @attr_reader [Regexp] cash_back The contents of the :match parameter, inside the yaml's :cash_back parameter (see
    #                                 above)
    # @attr_reader [String] cash_back_to The contents of the :to parameter, inside the yaml's :cash_back parameter (see
    #                                 above)
    # @attr_reader [TrueClass,FalseClass] reverse_order The contents of the yaml :reverse_order parameter (see above)
    # @attr_reader [String] default_currency The contents of the yaml :default_currency parameter (see above)
    class Reconciler
      include RVGP::Utilities

      # This error is thrown when a reconciler yaml is missing one or more require parameters
      class MissingFields < StandardError
        def initialize(*args)
          super format('One or more required keys %s, were missing in the yaml', args.map(&:inspect).join(', '))
        end
      end

      # @!visibility private
      # This class exists as an intermediary class, mostly to support the source
      # formats of both .csv and .journal files, without forcing one conform to the
      # other.
      class Posting
        attr_accessor :line_number, :date, :description, :commodity, :complex_commodity, :from, :to, :tags, :targets

        def initialize(line_number, opts = {})
          @line_number = line_number
          @date = opts[:date]
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
                                                 commodity: target[:commodity],
                                                 complex_commodity: target[:complex_commodity],
                                                 tags: target[:tags] ? target[:tags].map(&:to_tag) : nil
          end

          RVGP::Journal::Posting.new date,
                                     description,
                                     tags: tags ? tags.map(&:to_tag) : nil,
                                     transfers: transfers + [RVGP::Journal::Posting::Transfer.new(from)]
        end
      end

      attr_reader :label, :file, :output_file, :input_file, :starts_on, :balances, :disable_checks,
                  :from, :income_rules, :expense_rules, :tag_accounts, :cash_back, :cash_back_to,
                  :reverse_order, :default_currency

      # @!visibility private
      HEADER = ";;; %s --- Description -*- mode: ledger; -*-\n; vim: syntax=ledger"

      # Create a Reconciler from the provided yaml
      # @param [RVGP::Utilities::Yaml] yaml A file containing the settings to use in the construction of this reconciler
      #                                   . (see above)
      def initialize(yaml)
        @label = yaml[:label]
        @file = yaml.path
        @dependencies = yaml.dependencies

        @starts_on = yaml.key?(:starts_on) ? Date.strptime(yaml[:starts_on], '%Y-%m-%d') : nil

        missing_fields = %i[label output input from income expense].find_all { |attr| !yaml.key? attr }

        raise MissingFields.new(*missing_fields) unless missing_fields.empty?

        if RVGP.app
          @output_file = RVGP.app.config.build_path format('journals/%s', yaml[:output])
          @input_file = RVGP.app.config.project_path format('feeds/%s', yaml[:input])
        else
          # ATM this path is found in the test environment... possibly we should
          # decouple RVGP.app from this class....
          @output_file = yaml[:output]
          @input_file = yaml[:input]
        end

        @from = yaml[:from]
        @income_rules = yaml[:income]
        @expense_rules = yaml[:expense]
        @transform_commodities = yaml[:transform_commodities] || {}
        @balances = yaml[:balances]
        @disable_checks = yaml[:disable_checks]&.map(&:to_sym) if yaml.key?(:disable_checks)
        @disable_checks ||= []

        if yaml.key? :tag_accounts
          @tag_accounts = yaml[:tag_accounts]

          unless @tag_accounts.all? { |ta| %i[account tag].all? { |k| ta.key? k } }
            raise StandardError, 'One or more tag_accounts entries is missing an :account or :tag key'
          end
        end

        if yaml.key? :format
          @default_currency = yaml[:format][:default_currency] || '$'
          @reverse_order = yaml[:format][:reverse_order] if yaml[:format].key? :reverse_order

          if yaml[:format].key?(:cash_back)
            @cash_back = string_to_regex yaml[:format][:cash_back][:match]
            @cash_back_to = yaml[:format][:cash_back][:to]
          end
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
        (as_taskname == str ||
        from == str ||
        label == str ||
        file == str_as_file ||
        input_file == str_as_file ||
        output_file == str_as_file)
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
        if rule[:captures]
          rule[:to].scan(/\$([0-9a-z]+)/i).each do |substitutes|
            substitutes.each do |substitute|
              replace = rule[:captures][substitute]
              rule[:to].sub! format('$%s', substitute), replace if replace
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

          mod.to_tx posting
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

          to_target = { to: rule[:to], commodity: residual_commodity }

          to_target[:tags] = [rule[:to_tag]] if rule[:to_tag]
          posting.targets << to_target

          posting
        end
      end

      # @!visibility private
      def postings
        @postings ||= (reverse_order ? source_postings.reverse! : source_postings).map do |source_posting|
          # See what rule applies to this posting:
          rule = match_rule source_posting.commodity.positive? ? expense_rules : income_rules, source_posting

          # Reconcile the posting, according to that rule:
          Array(reconcile_posting(rule, source_posting)).flatten.compact.map do |posting|
            tag_accounts&.each do |tag_rule|
              # Note that we're operating under a kind of target model here, where
              # the posting itself isnt tagged, but the targets of the posting are.
              # This is a bit different than the reconcile_posting
              posting.targets.each do |target|
                # NOTE: This section should possibly DRY up with the
                # reconcile_posting() method
                next if yaml_rule_matches_string(tag_rule[:account_is_not], target[:to]) ||
                        yaml_rule_matches_string(tag_rule[:from_is_not], posting.from) ||
                        yaml_rule_matches_string(tag_rule[:account], target[:to], :!=) ||
                        yaml_rule_matches_string(tag_rule[:from], posting.from, :!=)

                target[:tags] ||= []
                target[:tags] << tag_rule[:tag]
              end
            end

            # And now we can convert it to the journal posting format
            journal_posting = posting.to_journal_posting

            # NOTE: Might want to return a row number here if it ever triggers:
            raise format('Invalid Transaction found %s', journal_posting.inspect) unless journal_posting.valid?

            # Cull only the transactions after the specified date:
            next if starts_on && journal_posting.date < starts_on

            journal_posting
          end
        end.flatten.compact
      end

      # @!visibility private
      def match_rule(rules, posting)
        rules.each_with_index do |rule, i|
          captures = nil

          if rule.key? :match
            isnt_matching, captures = *yaml_rule_matches_string_with_capture(rule[:match], posting.description, :!=)
            next if isnt_matching
          end

          if rule.key? :account
            # :account was added when we added journal_reconcile
            isnt_matching, captures = *yaml_rule_matches_string_with_capture(rule[:account], posting.to, :!=)
            next if isnt_matching
          end

          next if yaml_rule_asserts_commodity(rule[:amount_less_than], posting.commodity, :>=) ||
                  yaml_rule_asserts_commodity(rule[:amount_greater_than], posting.commodity, :<=) ||
                  yaml_rule_asserts_commodity(rule[:amount_equals], posting.commodity, :!=) ||
                  yaml_rule_matches_date(rule[:on_date], posting.date, :!=) ||
                  (rule.key?(:before_date) && posting.date >= rule[:before_date]) ||
                  (rule.key?(:after_date) && posting.date < rule[:after_date])

          # Success, there was a match:
          return rule.merge(index: i, captures: captures)
        end

        nil
      end

      # Builds the contents of this reconcilere's output file, and returns it. This is the finished
      # product of this class
      # @return [String] a PTA journal, composed of the input_file's transactions, after all rules are applied.
      def to_ledger
        [HEADER % label, postings.map(&:to_ledger), ''].flatten.join("\n\n")
      end

      # Writes the contents of #to_ledger, to the :output_file specified in the reconciler yaml.
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

        Dir.glob(format('%s/app/reconcilers/*.yml', directory_path)).map do |path|
          yaml = RVGP::Utilities::Yaml.new path, RVGP.app.config.project_path

          raise MissingFields.new, :input unless yaml.key? :input

          # We could probably make this a registry, though, I'd like to support
          # web addresses eventually. So, probably this designe pattern would
          # have to just be reconsidered entirely around that time.
          case File.extname(yaml[:input])
          when '.csv' then RVGP::Reconcilers::CsvReconciler.new(yaml)
          when '.journal' then RVGP::Reconcilers::JournalReconciler.new(yaml)
          else
            raise StandardError, format('Unrecognized file extension for input file "%s"', yaml[:input])
          end
        end
      end

      private

      def yaml_rule_matches_string(*args)
        yaml_rule_matches_string_with_capture(*args).first
      end

      def yaml_rule_matches_date(*args)
        yaml_rule_matches_string_with_capture(*args) { |date| date.strftime('%Y-%m-%d') }.first
      end

      def yaml_rule_matches_string_with_capture(rule_value, target_value, operation = :==, &block)
        return [false, nil] unless rule_value

        if (matcher = string_to_regex(rule_value.to_s))
          target_value_as_s = block_given? ? block.call(target_value) : target_value.to_s

          matches = matcher.match target_value_as_s

          [(operation == :== && matches) || (operation == :!= && matches.nil?),
           matches && matches.length > 1 ? matches.named_captures.dup : nil]
        else
          [rule_value.send(operation, target_value), nil]
        end
      end

      # NOTE: We compare a little unintuitively, wrt to testing the code, before testing the equivalence.
      # this is because we may be comparing a Commodity to a ComplexCommodity. And, in that case, we can
      # offer some asserting based on the code, by doing so.
      def yaml_rule_asserts_commodity(rule_value, target_value, operation = :==)
        return false unless rule_value

        rule_commodity = rule_value.to_s.to_commodity
        target_commodity = target_value.to_s.to_commodity

        target_commodity.alphabetic_code != rule_commodity.alphabetic_code ||
          target_commodity.abs.send(operation, rule_commodity)
      end
    end
  end
end
