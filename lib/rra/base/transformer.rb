# frozen_string_literal: true

require_relative '../utilities'

module RRA
  module Base
    # Transformers are a cornerstone of the RRA build, and an integral part of your project. Transformers, take an input
    # file (Either a csv file or a journal file), and transform them into a reconciled pta journal. This class
    # implements most of the functionality needed to make that happen.
    #
    # Transformers take two files as input. Firstly, it takes an aforementioned input file. But, secondly, it takes a
    # yaml file with transformation directives. What follows is a guide on those directives.
    #
    # Most of your time spent in these files, will be spent adding rules to the income and expense sections (see
    # the 'Defining income and expense sections'). However, in order to get the transformer far enough into the parsing
    # logic to get to that section, you'll need to understand the general structure of these files.
    #
    # = The General Structure of Transformer Yaml's
    # Transformer yaml files are expected to be found in the app/transformer directory. Typically with a four-digit year
    # as the start of its filename, and a yml extension. Here's a simple example transformer directory:
    #   ~/ledger> lsd -1 app/transformers/
    #    2022-business-checking.yml
    #    2023-business-checking.yml
    #    2022-personal-checking.yml
    #    2023-personal-checking.yml
    #    2022-personal-saving.yml
    #    2023-personal-saving.yml
    #    2022-personal-amex.yml
    #    2023-personal-amex.yml
    # In this example directory, we can see eight transformers defined, on each of the years 2022 and 2023, for each of
    # the accounts: business-checking, personal-checking, personal-saving, and personal-amex. Each of these files will
    # reference a separate input. Each of this files will produce a journal, with a corresponding name in
    # build/journals.
    #
    # All transformer files, are required to have a :label, :output, :input, :from, :income, and :expense key defined.
    # Here's an example of a transformer, with all of these sections present. Let's take a look at the
    # '2023-personal-checking.yml' transformer, from above:
    #   from: "Personal:Assets:AcmeBank:Checking"
    #   label: "Personal AcmeBank:Checking (2023)"
    #   input: 2023-personal-basic-checking.csv
    #   output: 2023-personal-basic-checking.journal
    #   format:
    #     csv_headers: true
    #     fields:
    #       date: !!proc Date.strptime(row['Date'], '%m/%d/%Y')
    #       amount: !!proc >
    #         withdrawal, deposit = row[3..4].collect {|a| a.to_commodity unless a.empty?};
    #         ( deposit ? deposit.invert! : withdrawal ).quantity_as_s
    #       description: !!proc row['Description']
    #   income:
    #     - match: /.*/
    #       to: Personal:Income:Unknown
    #   expense:
    #     - match: /.*/
    #       to: Personal:Expenses:Unknown
    # This file has a number of fairly obvious fields, and some not-so obvious fields. Let's take a look at these fields
    # one by one:
    #
    # - *from* [String] - This is the pta account, that the transformer will ascribe as it's default source of funds.
    # - *label* [String] - This a label for the transformer, that is mostly just used for status output on the cli.
    # - *input* [String] - The filename/path to the input to this file. Typically this is a csv file, located in the
    #   project's 'feeds' directory.
    # - *output* [String] - The filename to output in the project's 'build/journals' directory.
    # - *format* [Hash] - This section defines the logic used to decode a csv into fields. Typically, this section is
    #   shared between multiple transformers by way of an 'include' directive, to a file in your
    #   config/ directory. More on this below.<br><br>
    #   Note the use of the !!proc directive. These values are explained in the 'Special yaml features'
    #   section.
    # - *income* [Array<Hash>] - This collection matches one or more income entries in the input file, and reconciles them to
    #   an output entry.
    # - *expense* [Array<Hash>] - This collection matches one or more expense entries in the input file, and reconciles them
    #   to an output entry.
    #
    # Income and expenses are nearly identical in their rules and features, and are further explained in the 'Defining
    # income and expense sections' below.
    #
    # In addition to these basic parameters, the following parameters are also supported in the root of your transformer
    # file:
    # - *transform_commodities* [Hash] - This directive can be used to convert commodities in the format specified by
    #   its keys, to the commodity specified in its values. For example, the following will ensure that all USD values
    #   encountered in the input file, are transcribed as '$' in the output files:
    #     transform_commodities:
    #       USD: '$'
    # - *balances* [Hash] - This feature raises an error, if the balance of the :from account on a given date(key)
    #   doesn't match the provided value. Here's an example of what this looks like in a transformer:
    #     balances:
    #       '2023-01-15': $ 2345.67
    #       '2023-06-15': $ 3456,78
    #   This feature is mostly implemented by the {RRA::Validations::BalanceValidation}, and is provided as a fail-safe,
    #   in which you can input the balance reported by the statements from your financial institution, and ensure your
    #   build is consistent with the expectation of that institution.
    # - *disable_checks* [Array<String>] - This declaration can be used to disable one or more of your journal validations. This
    #   is described in greater depth in the {RRA::Base::Validation} documentation. Here's a sample of this feature,
    #   which can be used to disable the balances section that was explained above:
    #     disable_checks:
    #       - balance
    # - *tag_accounts* [Array<Hash>] - This feature is preliminary, and subject to change. The gist of this feature, is that
    #   it offers a second pass, after the income/expense rules have applied. This pass enables additional tags to be
    #   applied to a posting, based on how that posting was transformed in the first pass. I'm not sure I like how this
    #   feature came out, so, I'm disinclined to document it for now. If there's an interest in this feature, I can
    #   stabilize it's support, and better document it.
    #
    # = Understanding 'format' parameters
    # The format section applies rules to the parsing of the input file. And, as such, some of these parameters are
    # specific to the format of the input file. These rules are typically specific to a financial instution's specific
    # output formatting. And, as such, are typically shared between multiple transformer files in the form of an
    # !!include directive (see below).
    #
    # == CSV specific format parameters
    # The parameters are specific to .csv input files.
    # - *fields* [Hash<String, Proc>] - This field is required for csv's. This hash contains a map of field names, to !!proc's.
    #   The supported (required) field keys are: date, amount, and description. The values for each of these keys
    #   is evaluated (in ruby), and provided a single parameter, 'row' which contains a row as returned from ruby's
    #   CSV.parse method. The example project, supplied by the new_project command, contains an easy implementation
    #   of this feature in action.
    # - *invert_amount* [bool] (default: false) - Whether to call the {RRA::Journal::Commodity#invert!} on every
    #   amount that's encountered in the input file
    # - *csv_headers* [bool] (default: false) - Whether or not the first row of the input file, contains column headers
    #   for the rows that follow.
    # - *skip_lines* [Integer, String] - This option will direct the transformer to skip over lines at the beginning of
    #   the input file. This can be specified either as a number, which indicates the number of lines to ignore. Or,
    #   alternatively, this can be specified as a RegExp (provided in the form of a yaml string). In which case, the
    #   transformer will begin to parse one character after the end of the regular expression match.
    # - *trim_lines* [Integer, String] - This option will direct the transformer to skip over lines at the end of
    #   the input file. This can be specified either as a number, which indicates the number of lines to trim. Or,
    #   alternatively, this can be specified as a RegExp (provided in the form of a yaml string). In which case, the
    #   transformer will trim the file up to one character to the left of the regular expression match.
    #
    # == CSV and Journal file parameters
    # These parameters are available to both .journal as well as .csv files.
    # - *default_currency* [String] (default: '$') - A currency to default amount's to, if a currency isn't specified
    # - *reverse_order* [bool] (default: false) - Whether to output transactions in the opposite order of how they were
    #   encoded in the input file.
    # - *cash_back* - TODO
    #
    # = Defining income and expense sections
    # TODO
    #
    # = Special yaml features
    # - TODO: !!include
    # - TODO: !!proc
    #
    # TODO
    # This class implements most of the transformer logic. And, exists as the base
    # class from which input-specific transformers inherit (RRA:Transformers:CsvTransformer,
    # RRA:Transformers:JournalTransformer)
    # @attr_reader [TODO] label
    # @attr_reader [TODO] file
    # @attr_reader [TODO] output_file
    # @attr_reader [TODO] input_file
    # @attr_reader [TODO] starts_on
    # @attr_reader [TODO] balances
    # @attr_reader [TODO] disable_checks,
    # @attr_reader [TODO] from
    # @attr_reader [TODO] income_rules
    # @attr_reader [TODO] expense_rules
    # @attr_reader [TODO] tag_accounts
    # @attr_reader [TODO] cash_back
    # @attr_reader [TODO] cash_back_to,
    # @attr_reader [TODO] reverse_order
    # @attr_reader [TODO] default_currency
    class Transformer
      include RRA::Utilities

      # This error is thrown when a transformer yaml is missing one or more require parameters
      class MissingFields < StandardError
        def initialize(*args)
          super format('One or more required keys %s, were missing in the yaml', args.map(&:inspect).join(', '))
        end
      end

      # This class exists as an intermediary class, mostly to support the source
      # formats of both .csv and .journal files, without forcing one conform to the
      # other.
      class Posting
        attr_accessor :line_number, :date, :description, :commodity,
                      :complex_commodity, :from, :to, :tags, :targets

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

        def to_journal_posting
          transfers = targets.map do |target|
            RRA::Journal::Posting::Transfer.new target[:to],
                                                commodity: target[:commodity],
                                                complex_commodity: target[:complex_commodity],
                                                tags: target[:tags] ? target[:tags].map(&:to_tag) : nil
          end

          RRA::Journal::Posting.new date,
                                    description,
                                    tags: tags ? tags.map(&:to_tag) : nil,
                                    transfers: transfers + [RRA::Journal::Posting::Transfer.new(from)]
        end
      end

      attr_reader :label, :file, :output_file, :input_file, :starts_on, :balances, :disable_checks,
                  :from, :income_rules, :expense_rules, :tag_accounts, :cash_back, :cash_back_to,
                  :reverse_order, :default_currency

      HEADER = "; -*- %s -*-¬\n; vim: syntax=ledger"

      REQUIRED_FIELDS = %w[label output input from income expense].map(&:to_sym)

      # NOTE: yaml is expected to be an RRA::Yaml
      def initialize(yaml)
        @label = yaml[:label]
        @file = yaml.path
        @dependencies = yaml.dependencies

        @starts_on = yaml.key?(:starts_on) ? Date.strptime(yaml[:starts_on], '%Y-%m-%d') : nil

        missing_fields = REQUIRED_FIELDS.find_all { |attr| !yaml.key? attr }
        raise MissingFields.new(*missing_fields) unless missing_fields.empty?

        if RRA.app
          @output_file = RRA.app.config.build_path format('journals/%s', yaml[:output])
          @input_file = RRA.app.config.project_path format('feeds/%s', yaml[:input])
        else
          # ATM this path is found in the test environment... possibly we should
          # decouple RRA.app from this class....
          @output_file = yaml[:output]
          @input_file = yaml[:input]
        end

        @from = yaml[:from]
        @income_rules = yaml[:income]
        @expense_rules = yaml[:expense]
        @transform_commodities = yaml[:transform_commodities] || {}
        @balances = yaml[:balances]
        @disable_checks = yaml.key?(:disable_checks) ? yaml[:disable_checks].map(&:to_sym) : []

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

      def as_taskname
        File.basename(file, File.extname(file)).tr('^a-z0-9', '-')
      end

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

      def dependencies
        [file, input_file] + @dependencies
      end

      def uptodate?
        FileUtils.uptodate? output_file, dependencies
      end

      # This file is used to mtime the last success
      def validated_touch_file_path
        format('%s.valid', output_file)
      end

      def mark_validated!
        FileUtils.touch validated_touch_file_path
      end

      def validated?
        FileUtils.uptodate? validated_touch_file_path, [output_file]
      end

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

      def transform_posting(rule, posting)
        # NOTE: The modules produce more than one tx per csv line, sometimes:

        to = rule[:to].dup
        posting.from = rule[:from] if rule.key? :from

        posting.tags << rule[:tag] if rule.key? :tag

        # Let's do a find and replace on the :to if we have anything captured
        # This is kind of rudimentary, and only supports named_caputers atm
        # but I think it's fine for now. Probably it's broken wrt cash back or
        # something...
        if rule[:captures]
          to.scan(/\$([0-9a-z]+)/i).each do |substitutes|
            substitutes.each do |substitute|
              replace = rule[:captures][substitute]
              to.sub! format('$%s', substitute), replace if replace
            end
          end
        end

        if rule.key? :to_module
          rule_key = posting.commodity.positive? ? :expense : :income

          @modules ||= {}
          @modules[rule_key] ||= {}
          mod = @modules[rule_key][rule[:index]]

          unless mod
            module_klass = format 'RRA::Transformers::Modules::%s', rule[:to_module]

            raise StandardError, format('Unknown module %s', module_klass) unless Object.const_defined?(module_klass)

            mod = Object.const_get(module_klass).new rule

            @modules[rule_key][rule[:index]] = mod
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
              commodity = RRA::Journal::Commodity.from_symbol_and_amount(
                rule_target[:currency] || default_currency,
                rule_target[:amount].to_s
              )
            elsif rule_target.key? :complex_commodity
              complex_commodity = RRA::Journal::ComplexCommodity.from_s(rule_target[:complex_commodity])
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
            cash_back_commodity = RRA::Journal::Commodity.from_symbol_and_amount(
              ::Regexp.last_match(1), Regexp.last_match(2)
            )
            residual_commodity -= cash_back_commodity
            posting.targets << { to: cash_back_to, commodity: cash_back_commodity }
          end

          posting.targets << { to: to, commodity: residual_commodity }

          posting
        end
      end

      def postings
        @postings ||= (reverse_order ? source_postings.reverse! : source_postings).map do |source_posting|
          # See what rule applies to this posting:
          rule = match_rule source_posting.commodity.positive? ? expense_rules : income_rules, source_posting

          # Transform the posting, according to that rule:
          Array(transform_posting(rule, source_posting)).flatten.compact.map do |posting|
            tag_accounts&.each do |tag_rule|
              # Note that we're operating under a kind of target model here, where
              # the posting itself isnt tagged, but the targets of the posting are.
              # This is a bit different than the transform_posting
              posting.targets.each do |target|
                # NOTE: This section should possibly DRY up with the
                # transform_posting() method
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

      def match_rule(rules, posting)
        rules.each_with_index do |rule, i|
          captures = nil

          if rule.key? :match
            isnt_matching, captures = *yaml_rule_matches_string_with_capture(rule[:match], posting.description, :!=)
            next if isnt_matching
          end

          if rule.key? :account
            # :account was added when we added journal_transform
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

      def to_ledger
        [HEADER % label, postings.map(&:to_ledger), ''].flatten.join("\n\n")
      end

      def to_ledger!
        File.write output_file, to_ledger
      end

      def self.all(directory_path)
        # NOTE: I'm not crazy about this method. Probably we should have
        # implemented a single Transformer class, with CSV/Journal drivers.
        # Nonetheless, this code works for now. Maybe if we add another
        # driver, we can renovate it, and add some kind of registry for drivers.

        Dir.glob(format('%s/app/transformers/*.yml', directory_path)).map do |path|
          yaml = RRA::Yaml.new path, RRA.app.config.project_path

          raise MissingFields.new, :input unless yaml.key? :input

          # We could probably make this a registry, though, I'd like to support
          # web addresses eventually. So, probably this designe pattern would
          # have to just be reconsidered entirely around that time.
          case File.extname(yaml[:input])
          when '.csv' then RRA::Transformers::CsvTransformer.new(yaml)
          when '.journal' then RRA::Transformers::JournalTransformer.new(yaml)
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
