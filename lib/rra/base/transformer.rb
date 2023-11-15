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
    #    2022-personal-amex.yml
    #    2023-personal-amex.yml
    #    2022-personal-checking.yml
    #    2023-personal-checking.yml
    #    2022-personal-saving.yml
    #    2023-personal-saving.yml
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
    #       amount: !!proc row['Amount']
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
    # - *starts_on* [String] - A cut-off date, before which, transactions in the input_file are ignored. Date is
    #                          expected to be provided in YYYY-MM-DD format.
    # - *format* [Hash] - This section defines the logic used to decode a csv into fields. Typically, this section is
    #   shared between multiple transformers by way of an 'include' directive, to a file in your
    #   config/ directory. More on this below.<br><br>
    #   Note the use of the !!proc directive. These values are explained in the 'Special yaml features'
    #   section.
    # - *income* [Array<Hash>] - This collection matches one or more income entries in the input file, and reconciles
    #   them to an output entry.
    # - *expense* [Array<Hash>] - This collection matches one or more expense entries in the input file, and reconciles
    #   them to an output entry.
    #
    # Income and expenses are nearly identical in their rules and features, and are further explained in the 'Defining
    # income and expense sections' below.
    #
    # In addition to these basic parameters, the following parameters are also supported in the root of your transformer
    # file:
    # - *transform_commodities* [Hash] - This directive can be used to convert commodities in the format specified by
    #   its keys, to the commodity specified in its values. For example, the following will ensure that all USD values
    #   encountered in the input file, are transcribed as '$' in the output files:
    #     ...
    #     transform_commodities:
    #       USD: '$'
    #     ...
    # - *balances* [Hash] - This feature raises an error, if the balance of the :from account on a given date(key)
    #   doesn't match the provided value. Here's an example of what this looks like in a transformer:
    #     ...
    #     balances:
    #       '2023-01-15': $ 2345.67
    #       '2023-06-15': $ 3456,78
    #     ...
    #   This feature is mostly implemented by the {RRA::Validations::BalanceValidation}, and is provided as a fail-safe,
    #   in which you can input the balance reported by the statements from your financial institution, and ensure your
    #   build is consistent with the expectation of that institution.
    # - *disable_checks* [Array<String>] - This declaration can be used to disable one or more of your journal
    #   validations. This is described in greater depth in the {RRA::Base::Validation} documentation. Here's a sample
    #   of this feature, which can be used to disable the balances section that was explained above:
    #     ...
    #     disable_checks:
    #       - balance
    #     ...
    # - *tag_accounts* [Array<Hash>] - This feature is preliminary, and subject to change. The gist of this feature, is
    #   that it offers a second pass, after the income/expense rules have applied. This pass enables additional tags to
    #   be applied to a posting, based on how that posting was transformed in the first pass. I'm not sure I like how
    #   this feature came out, so, I'm disinclined to document it for now. If there's an interest in this feature, I can
    #   stabilize it's support, and better document it.
    #
    # = Understanding 'format' parameters
    # The format section applies rules to the parsing of the input file. Some of these parameters are
    # specific to the format of the input file. These rules are typically specific to a financial instution's specific
    # output formatting. And are typically shared between multiple transformer files in the form of an
    # !!include directive (see below).
    #
    # == CSV specific format parameters
    # The parameters are specific to .csv input files.
    # - *fields* [Hash<String, Proc>] - This field is required for csv's. This hash contains a map of field names, to
    #   !!proc's. The supported (required) field keys are: date, amount, and description. The values for each of these
    #   keys is evaluated (in ruby), and provided a single parameter, 'row' which contains a row as returned from ruby's
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
    # - *cash_back* [Hash] - This feature enables you to match transaction descriptions for a cash back indication and
    #   amount, and to break that component of the charge into a separate account. The valid keys in this hash are
    #   :match and :to . The matched captures of the regex are assumed to be symbol (1) and amount (2), which are used
    #   to construct a commodity that's assigned to the :to value. Here's an easy exmple
    #     ...
    #     cash_back:
    #       match: '/\(CASH BACK: ([^ ]) ([\d]+\.[\d]{2})\)\Z/'
    #       to: Personal:Assets:Cash
    #     ...
    #
    # = Defining income and expense sections
    # This is where you'll spend most of your time reconciling. Once the basic csv structure is parsing, these sections
    # are how you'll match entries in your input file, and turn them into reconciled output entries. The income_rules
    # and expense_rules are governed by the same logic. Let's breakout some of their rules, that you should understand:
    # - The *_rules section of the yaml is a array of hashes
    # - These hashes contain 'match' directives, and 'assignment' directives
    # - All transactions in the input file, are sent to either income_rules, or expense_rules, depending on whether
    #   their amount is a credit(income), or a debit(expense).
    # - Each transaction in the input file is sent down the chain of rules (either income or expense) from the top of
    #   the list, towards the bottom - until a matching rule is found. At that time, traversal will stop. And, all
    #   directives in this rule will apply to the input transaction.
    # - If you've ever managed a firewall, this matching and directive process works very similarly to how packets are
    #   managed by a firewall ruleset.
    # - If no matches were found, an error is raised. Typically, you'll want a catch-all at the end of the chain, like
    #   so:
    #    ...
    #    - match: /.*/
    #      to: Personal:Expenses:Unknown
    #
    # For every hash in an array of income and expense rules, you can specify one or more of the following yaml
    # directives. Note that these directives all serve to provide two function: matching input transactions, indicating
    # how to reconcile any matches it captures.
    #
    # == Income & Expense Rules: Matching
    # The following directives are matching rules. If more than one of these directives are encountered in a rule,
    # they're and'd together. Meaning: all of the conditions that are listed, need to apply to subject, in order for a
    # match to execute.
    # - *match* [Regexp,String] - If a string is provided, compares the :description of the feed transaction against the
    #   value provided, and matches if they're equal. If a regex is provided, matches the
    #   :description of the feed transaction against the regex provided.
    #   If a regex is provided, captures are supported. (see the note below)
    # - *account* [Regexp,String] - This matcher is useful for transformers that support the :to field.
    #   (see {RRA::Transformers::JournalTransformer}). If a string is provided, compares the
    #   account :to which a transaction was assigned, to the value provided. And matches if
    #   they're equal. If a regex is provided, matches the account :to which a transaction
    #   was assigned, against the regex provided.
    #   If a regex is provided, captures are supported. (see the note below)
    # - *account_is_not* [String] - This matcher is useful for transformers that support the :to field.
    #   (see {RRA::Transformers::JournalTransformer}). This field matches any transaction
    #   whose account :to, does not equal the provided string.
    # - *amount_less_than* [Commodity] - This field compares it's value to the transaction :amount , and matches if
    #   that amount is less than the provided amount.
    # - *amount_greater_than* [Commodity] - This field compares it's value to the transaction :amount , and matches
    #   if that amount is greater than the provided amount.
    # - *amount_equals* [Commodity] - This field compares it's value to the transaction :amount , and matches if
    #   that amount is equal to the provided amount.
    # - *on_date* [Regexp,Date] - If a date is provided, compares the :date of the feed transaction against the value
    #   provided, and matches if they're equal. If a regex is provided, matches the
    #   :date of the feed, converted to a string in the format 'YYYY-MM-DD', against the regex
    #   provided.
    #   If a regex is provided, captures are supported. (see the note below)
    # - *before_date* [Date] - This field compares it's value to the feed transaction :date, and matches if the feed's
    #   :date occurred before the provided :date.
    # - *after_date* [Date] - This field compares it's value to the feed transaction :date, and matches if the feed's
    #   :date occurred after the provided :date.
    # - *from_is_not* [String] - This field matches any transaction whose account :from, does not equal the provided
    #   string.
    #
    # *NOTE* Some matchers which support captures: This is a powerful feature that allows regexp captured values, to
    # substitute in the :to field of the transformed transaction. Here's an example of how this feature works:
    #  - match: '/^Reservation\: (?<unit>[^ ]+)/'
    #    to: AirBNB:Income:$unit
    # In this example, the text that existed in the "(?<unit>[^ ]+)" section of the 'match' field, is substituted in
    # place of "$unit" in the output journal.
    #
    # == Income & Expense Rules: Reconciliation
    # The following directives are reconciliation rules. These rules have nothing to do with matching, and instead
    # apply to the outputted transaction for the rule in which they're declared. If more than one of these rules are
    # present - they all apply.
    # - *to* [String] - This field will provide the :to account to reconcile an input transaction against. Be aware
    #   aware of the above note on captures, as this field supports capture variable substitution.
    # - *from* [String] - This field can be used to change the reconciled :from account, to a different account than
    #   the default :from, that was specified in the root of the transformer yaml.
    # - *tag* [String] - Tag(s) to apply to the reconciled transaction.
    # - *targets* [Array<Hash>] - For some transactions, multiple transfers need to expand from a single input
    #   transaction. In those cases, :targets is the reconciliation rule you'll want to use.
    #   This field is expected to be an array of Hashes. With, each hash supporting the
    #   following fields:
    #   - *to* [String] - As with the above :to, this field will provide the account to reconcile the transfer to.
    #   - *amount* [Commodity] - The amount to ascribe to this transfer. While the sum of the targets 'should' equal the
    #     input transaction amount, there is no validation performed by RRA to do so. So, excercize discretion when
    #     manually breaking out input transactions into multiple transfers.
    #   - *complex_commodity* [ComplexCommodity] - A complex commodity to ascribe to this transfer, instead of an
    #     :amount. See {RRA::Journal::ComplexCommodity.from_s} for more details on this feature.
    #   - *tags* [Array<String>] - An array of tags to assign to this transfer. See {RRA::Journal::Posting::Tag.from_s}
    #     for more details on tag formatting.
    # - *to_module* [String] - Transformer Modules are a powerful feature that can reduce duplication, and manual
    #   calculations from your transformer yaml. The value provided here, must correlate with an
    #   available transformer module, and if so, sends this rule to that module for
    #   reconciliation.
    # - *module_params* [Hash] - This section is specific to the transformer module that was specified in the :to_module
    #   field. Any of the key/value pairs specified here, are sent to the transformer module,
    #   along with the rest of the input transaction. And, presumably, these fields will futher
    #   direct the reconciliation of the input transaction.
    #
    # = Special yaml features
    # All of these pysch extensions, are prefixed with two exclamation points, and can be placed in lieu of a value, for
    # some of the fields outlined above.
    # - <b>!!include</b> [String] - Include another yaml file, in place of this directive. The file is expected to be
    #   provided, immediately followed by this declaration (separated by a space). It's common to see this directive
    #   used as a shortcut to shared :format sections. But, these can be used almost anywhere. Here's an example:
    #     ...
    #     from: "Personal:Assets:AcmeBank:Checking"
    #     label: "Personal AcmeBank:Checking (2023)"
    #     format: !!include config/csv-format-acmebank.yml
    #     ...
    # - <b>!!proc</b> [String] - Convert the contents of the text following this directive, into a Proc object. It'
    #   common to see this directive used in the format section of a transformer yaml. Here's an example:
    #     ...
    #     fields:
    #     date: !!proc >
    #       date = Date.strptime(row[0], '%m/%d/%Y');
    #       date - 1
    #     amount: !!proc row[1]
    #     description: !!proc row[2]
    #     ...
    #   Note that the use of '>' is a yaml feature, that allows multiline strings to compose by way of an indent in
    #   the lines that follow. For one-line '!!proc' declarations, this character is not needed. Additionally, this
    #   means that in most cases, carriage returns are not parsed. As such, you'll want to terminate lines in these
    #   segments, with a semicolon, to achieve the same end.
    #
    # @attr_reader [String] label The contents of the yaml :label parameter (see above)
    # @attr_reader [String] file The full path to the transformer yaml file this class was parsed from
    # @attr_reader [String] output_file The contents of the yaml :output parameter (see above)
    # @attr_reader [String] input_file The contents of the yaml :input parameter (see above)
    # @attr_reader [Date] starts_on The contents of the yaml :starts_on parameter (see above)
    # @attr_reader [Hash<String, String>] balances A hash of dates (in 'YYYY-MM-DD') to commodities (as string)
    #                                              corresponding to the balance that are expected on those dates.
    #                                              See {RRA::Validations::BalanceValidation} for details on this
    #                                              feature.
    # @attr_reader [Array<String>] disable_checks The JournalValidations that are disabled on this transformer (see
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
    class Transformer
      include RRA::Utilities

      # This error is thrown when a transformer yaml is missing one or more require parameters
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

      # @!visibility private
      HEADER = "; -*- %s -*-¬\n; vim: syntax=ledger"

      # Create a Transformer from the provided yaml
      # @param [RRA::Yaml] yaml A file containing the settings to use in the construction of this transformer.
      #                         (see above)
      def initialize(yaml)
        @label = yaml[:label]
        @file = yaml.path
        @dependencies = yaml.dependencies

        @starts_on = yaml.key?(:starts_on) ? Date.strptime(yaml[:starts_on], '%Y-%m-%d') : nil

        missing_fields = %i[label output input from income expense].find_all { |attr| !yaml.key? attr }

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

      # Returns the taskname to use by rake, for this transformer
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

      # Returns the file paths that were referenced by this transformer in one form or another.
      # Useful for determining build freshness.
      # @return [Array<String>] dependent files, in this transformer.
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

      # @!visibility private
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

      # @!visibility private
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

      # Builds the contents of this transformere's output file, and returns it. This is the finished
      # product of this class
      # @return [String] a PTA journal, composed of the input_file's transactions, after all rules are applied.
      def to_ledger
        [HEADER % label, postings.map(&:to_ledger), ''].flatten.join("\n\n")
      end

      # Writes the contents of #to_ledger, to the :output_file specified in the transformer yaml.
      # @return [void]
      def to_ledger!
        File.write output_file, to_ledger
      end

      # Returns an array of all of the transformers found in the specified path.
      # @param [String] directory_path The path containing your yml transformer files
      # @return [Array<RRA::Transformers::CsvTransformer, RRA::Transformers::JournalTransformer>]
      #   An array of parsed transformers.
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
