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
    # @attr_reader [Hash] input_format These are (usually shared) formatting directives to use in the
    # transformation of the input file, into the intermediate format used to construct a posting
    # @option input_format [Hash<String, <Proc,String,Integer>>] fields_format A hash of field names, to their location in
    #   the input file. Supported key names include: date, effective_date, amount, description. These keys can map
    #   to either a 'string' type (indicating which column of the input file contains the key's value). An Integer
    #   (indicating which column offset contains the key's value). Or, a Proc (which executes for every row in the
    #   input file, and whose return value will be used)
    # @option input_format [Boolean] csv_headers True if the first row of the provided csv contains field
    # header names
    # @option input_format [Boolean] invert_amount Whether or not to multiple the :amount field by negative one.
    # @option input_format [<Regexp, Integer>] skip_lines Given a regex, the input file will discard the match for the
    #   provided regex from the start of the input file. Given an integer, the provided number of lines will be
    #   removed from the start of the input file.
    # @option input_format [<Regexp, Integer>] trim_lines Given a regex, the input file will discard the match for the
    #   provided regex from the end of the input file. Given an integer, the provided number of lines will be
    #   removed from the end of the input file.
    # @option input_format [<Proc>] filter_contents A procedure, provided in the yaml, that is used to modify the csv
    #   contents.
    # @option input_format [String] default_currency The contents of the yaml :default_currency parameter (see above)
    # @option input_format [Boolean] reverse_order The contents of the yaml :reverse_order parameter (see above)
    class YamlReconciler < RVGP::Base::Reconciler
      # This error is thrown when a reconciler yaml is missing one or more require parameters
      class MissingFields < StandardError
        def initialize(*args)
          super(format('One or more required keys %s, were missing in the yaml', args.map(&:inspect).join(', ')))
        end
      end

      attr_reader :starts_on, :ends_on, :balances, :from, :income_rules, :expense_rules, :tag_accounts,
                  :cash_back, :cash_back_to, :input_format

      # Create a Reconciler from the provided yaml
      # @param [RVGP::Utilities::Yaml] yaml A file containing the settings to use in the construction of this reconciler
      #                                   . (see above)
      def initialize(yaml)
        missing_fields = %i[label output input from income expense].find_all { |attr| !yaml.key? attr }

        raise MissingFields.new(*missing_fields) unless missing_fields.empty?

        @starts_on = yaml.key?(:starts_on) ? Date.strptime(yaml[:starts_on], '%Y-%m-%d') : nil
        @ends_on = yaml.key?(:ends_on) ? Date.strptime(yaml[:ends_on], '%Y-%m-%d') : nil
        @from = yaml[:from]
        @income_rules = yaml[:income]
        @expense_rules = yaml[:expense]
        @transform_commodities = yaml[:transform_commodities] || {}
        @balances = yaml[:balances]

        if RVGP.app
          @output_file = RVGP.app.config.build_path format('journals/%s', yaml[:output])
          @input_file = RVGP.app.config.project_path format('feeds/%s', yaml[:input])
        else
          # ATM this path is found in the test environment... possibly we should
          # decouple RVGP.app from this class....
          @output_file = yaml[:output]
          @input_file = yaml[:input]
        end

        if yaml.key? :tag_accounts
          @tag_accounts = yaml[:tag_accounts]

          unless @tag_accounts.all? { |ta| %i[account tag].all? { |k| ta.key? k } }
            raise StandardError, 'One or more tag_accounts entries is missing an :account or :tag key'
          end
        end

        @input_format = yaml[:format].to_h || {}
        @input_format[:default_currency] || '$'

        cash_back = @input_format.delete(:cash_back)
        if cash_back
          @cash_back = string_to_regex cash_back[:match]
          @cash_back_to = cash_back[:to]
        end

        super(yaml.path,
              label: yaml[:label],
              dependencies: yaml.dependencies,
              disable_checks: yaml.key?(:disable_checks) ? yaml[:disable_checks]&.map(&:to_sym) : nil)
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
                rule_target[:currency] || @format[:default_currency],
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

      # @!visibility private
      def postings
        @postings ||= source_postings.map do |source_posting|
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
