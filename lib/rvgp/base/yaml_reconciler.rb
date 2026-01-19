# lib/yaml_reconciler.rb

module RVGP
  module Base
    # See {RVGP::Reconcilers} for extensive detail on the structure and function of reconciler yaml files, and
    # reconciler functionality.
    #
    # @attr_reader [String] label The contents of the yaml :label parameter (see above)
    # @attr_reader [String] file The full path to the reconciler yaml file this class was parsed from
    # @attr_reader [String] input_file The contents of the yaml :input parameter (see above)
    # @attr_reader [String] output_file The contents of the yaml :output parameter (see above)
    # @attr_reader [Date] starts_on The contents of the yaml :starts_on parameter (see above)
    # @attr_reader [Date] ends_on The contents of the yaml :ends_on parameter (see above)
    # @attr_reader [Hash<String, String>] balances A hash of dates (in 'YYYY-MM-DD') to commodities (as string)
    #                                              corresponding to the balance that are expected on those dates.
    #                                              See {RVGP::Validations::BalanceValidation} for details on this
    #                                              feature.
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
    class YamlReconciler < RVGP::Base::Reconciler
      # This error is thrown when a reconciler yaml is missing one or more require parameters
      class MissingFields < StandardError
        def initialize(*args)
          super(format('One or more required keys %s, were missing in the yaml', args.map(&:inspect).join(', ')))
        end
      end

      attr_reader :starts_on, :ends_on, :balances, :from, :income_rules, :expense_rules, :tag_accounts,
                  :cash_back, :cash_back_to, :reverse_order, :default_currency

      # Create a Reconciler from the provided yaml
      # @param [RVGP::Utilities::Yaml] yaml A file containing the settings to use in the construction of this reconciler
      #                                   . (see above)
      def initialize(yaml)
        @label = yaml[:label]
        @file = yaml.path
        @dependencies = yaml.dependencies

        @starts_on = yaml.key?(:starts_on) ? Date.strptime(yaml[:starts_on], '%Y-%m-%d') : nil
        @ends_on = yaml.key?(:ends_on) ? Date.strptime(yaml[:ends_on], '%Y-%m-%d') : nil

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

        super
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
            next if ends_on && journal_posting.date > ends_on

            journal_posting
          end
        end.flatten.compact
      end

      # @!visibility private
      def matches_argument?(str)
        super || from == str
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

      def self.all(from_path)
        yaml = RVGP::Utilities::Yaml.new from_path, RVGP.app.config.project_path

        raise MissingFields.new, :input unless yaml.key? :input

        case File.extname(yaml[:input])
        when '.csv' then [RVGP::Reconcilers::CsvReconciler.new(yaml)]
        when '.journal' then [RVGP::Reconcilers::JournalReconciler.new(yaml)]
        else
          raise StandardError, format('Unrecognized file extension for input file "%s"', yaml[:input])
        end
      end

      private

      def yaml_rule_matches_string(*)
        yaml_rule_matches_string_with_capture(*).first
      end

      def yaml_rule_matches_date(*)
        yaml_rule_matches_string_with_capture(*) { |date| date.strftime('%Y-%m-%d') }.first
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
