# frozen_string_literal: true

require 'csv'
require_relative '../journal'

module RVGP
  # Reconcilers are a cornerstone of the RVGP build, and an integral part of your project. Reconcilers, take an input
  # file (Either a csv file or a journal file), and reconcile them into a reconciled pta journal. This class
  # implements most of the functionality needed to make that happen.
  #
  # Reconcilers take two files as input. Firstly, it takes an aforementioned input file. But, secondly, it takes a
  # yaml file with reconciliation directives. What follows is a guide on those directives.
  #
  # Most of your time spent in these files, will be spent adding rules to the income and expense sections (see
  # the 'Defining income and expense sections'). However, in order to get the reconciler far enough into the parsing
  # logic to get to that section, you'll need to understand the general structure of these files.
  #
  # ## The General Structure of Reconciler Yaml's
  # Reconciler yaml files are expected to be found in the app/reconciler directory. Typically with a four-digit year
  # as the start of its filename, and a yml extension. Here's a simple example reconciler directory:
  # ```
  # ~/ledger> lsd -1 app/reconcilers/
  #  2022-business-checking.yml
  #  2023-business-checking.yml
  #  2022-personal-amex.yml
  #  2023-personal-amex.yml
  #  2022-personal-checking.yml
  #  2023-personal-checking.yml
  #  2022-personal-saving.yml
  #  2023-personal-saving.yml
  # ```
  # In this example directory, we can see eight reconcilers defined, on each of the years 2022 and 2023, for each of
  # the accounts: business-checking, personal-checking, personal-saving, and personal-amex. Each of these files will
  # reference a separate input. Each of this files will produce a journal, with a corresponding name in
  # build/journals.
  #
  # All reconciler files, are required to have a :label, :output, :input, :from, :income, and :expense key defined.
  # Here's an example of a reconciler, with all of these sections present. Let's take a look at the
  # '2023-personal-checking.yml' reconciler, from above:
  # ```
  # from: "Personal:Assets:AcmeBank:Checking"
  # label: "Personal AcmeBank:Checking (2023)"
  # input: 2023-personal-basic-checking.csv
  # output: 2023-personal-basic-checking.journal
  # format:
  #   csv_headers: true
  #   fields:
  #     date: !!proc Date.strptime(row['Date'], '%m/%d/%Y')
  #     amount: !!proc row['Amount']
  #     description: !!proc row['Description']
  # income:
  #   - match: /.*/
  #     to: Personal:Income:Unknown
  # expense:
  #   - match: /.*/
  #     to: Personal:Expenses:Unknown
  # ```
  #
  # This file has a number of fairly obvious fields, and some not-so obvious fields. Let's take a look at these fields
  # one by one:
  #
  # - **from** [String] - This is the pta account, that the reconciler will ascribe as it's default source of funds.
  # - **label** [String] - This a label for the reconciler, that is mostly just used for status output on the cli.
  # - **input** [String] - The filename/path to the input to this file. Typically this is a csv file, located in the
  #   project's 'feeds' directory.
  # - **output** [String] - The filename to output in the project's 'build/journals' directory.
  # - **starts_on** [String] - A cut-off date, before which, transactions in the input file are ignored. Date is
  #                          expected to be provided in YYYY-MM-DD format.
  # - **format** [Hash] - This section defines the logic used to decode a csv into fields. Typically, this section is
  #   shared between multiple reconcilers by way of an 'include' directive, to a file in your
  #   config/ directory. More on this below.<br><br>
  #   Note the use of the !!proc directive. These values are explained in the 'Special yaml features'
  #   section.
  # - **income** [Array<Hash>] - This collection matches one or more income entries in the input file, and reconciles
  #   them to an output entry.
  # - **expense** [Array<Hash>] - This collection matches one or more expense entries in the input file, and reconciles
  #   them to an output entry.
  #
  # Income and expenses are nearly identical in their rules and features, and are further explained in the 'Defining
  # income and expense sections' below.
  #
  # In addition to these basic parameters, the following parameters are also supported in the root of your reconciler
  # file:
  # - **transform_commodities** [Hash] - This directive can be used to convert commodities in the format specified by
  #   its keys, to the commodity specified in its values. For example, the following will ensure that all USD values
  #   encountered in the input file, are transcribed as '$' in the output files:
  #
  #         ...
  #         transform_commodities:
  #           USD: '$'
  #         ...
  #
  # - **balances** [Hash] - This feature raises an error, if the balance of the :from account on a given date(key)
  #   doesn't match the provided value. Here's an example of what this looks like in a reconciler:
  #
  #         ...
  #         balances:
  #           '2023-01-15': $ 2345.67
  #           '2023-06-15': $ 3456,78
  #         ...
  #   This feature is mostly implemented by the {RVGP::Validations::BalanceValidation}, and is provided as a
  #   fail-safe, in which you can input the balance reported by the statements from your financial institution,
  #   and ensure your build is consistent with the expectation of that institution.
  # - **disable_checks** [Array<String>] - This declaration can be used to disable one or more of your journal
  #   validations. This is described in greater depth in the {RVGP::Base::Validation} documentation. Here's a sample
  #   of this feature, which can be used to disable the balances section that was explained above:
  #
  #         ...
  #         disable_checks:
  #           - balance
  #         ...
  # - **tag_accounts** [Array<Hash>] - This feature is preliminary, and subject to change. The gist of this feature, is
  #   that it offers a second pass, after the income/expense rules have applied. This pass enables additional tags to
  #   be applied to a posting, based on how that posting was reconciled in the first pass. I'm not sure I like how
  #   this feature came out, so, I'm disinclined to document it for now. If there's an interest in this feature, I can
  #   stabilize it's support, and better document it.
  #
  # ## Understanding 'format' parameters
  # The format section applies rules to the parsing of the input file. Some of these parameters are
  # specific to the format of the input file. These rules are typically specific to a financial instution's specific
  # output formatting. And are typically shared between multiple reconciler files in the form of an
  # !!include directive (see below).
  #
  # ### CSV specific format parameters
  # The parameters are specific to .csv input files.
  # - **fields** [Hash<String, Proc>] - This field is required for csv's. This hash contains a map of field names, to
  #   !!proc's. The supported (required) field keys are: date, amount, and description. The values for each of these
  #   keys is evaluated (in ruby), and provided a single parameter, 'row' which contains a row as returned from ruby's
  #   CSV.parse method. The example project, supplied by the new_project command, contains an easy implementation
  #   of this feature in action.
  # - **invert_amount** [bool] (default: false) - Whether to call the {RVGP::Journal::Commodity#invert!} on every
  #   amount that's encountered in the input file
  # - **encoding** [String] - This parameter is passed to the :encoding parameter of File.read, during the parsing of
  #   the supplied input file. This can be used to prevent CSV::MalformedCSVError in cases such as a bom encoded
  #   input file.
  # - **csv_headers** [bool] (default: false) - Whether or not the first row of the input file, contains column headers
  #   for the rows that follow.
  # - **skip_lines** [Integer, String] - This option will direct the reconciler to skip over lines at the beginning of
  #   the input file. This can be specified either as a number, which indicates the number of lines to ignore. Or,
  #   alternatively, this can be specified as a RegExp (provided in the form of a yaml string). In which case, the
  #   reconciler will begin to parse one character after the end of the regular expression match.
  # - **trim_lines** [Integer, String] - This option will direct the reconciler to skip over lines at the end of
  #   the input file. This can be specified either as a number, which indicates the number of lines to trim. Or,
  #   alternatively, this can be specified as a RegExp (provided in the form of a yaml string). In which case, the
  #   reconciler will trim the file up to one character to the left of the regular expression match.
  # - **filter_contents** [Proc] - This field is intended for use in modifying the csv file, before passing it on to
  #   rvgp for normal processing. The code in this filed will be provided 'contents', a string containing the contents
  #   of the csv file, and 'path' containing the path of the csv file. A string is expected to be returned, which, will
  #   be used in lieu of the contents that would otherwise be evaluated.
  #
  # ### CSV and Journal file format parameters
  # These parameters are available to both .journal as well as .csv files.
  # - **default_currency** [String] (default: '$') - A currency to default amount's to, if a currency isn't specified
  # - **reverse_order** [bool] (default: false) - Whether to output transactions in the opposite order of how they were
  #   encoded in the input file.
  # - **cash_back** [Hash] - This feature enables you to match transaction descriptions for a cash back indication and
  #   amount, and to break that component of the charge into a separate account. The valid keys in this hash are
  #   :match and :to . The matched captures of the regex are assumed to be symbol (1) and amount (2), which are used
  #   to construct a commodity that's assigned to the :to value. Here's an easy exmple
  #
  #         ...
  #         cash_back:
  #           match: '/\(CASH BACK: ([^ ]) ([\d]+\.[\d]{2})\)\Z/'
  #           to: Personal:Assets:Cash
  #         ...
  #
  # ## Defining income and expense sections
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
  #
  #         ...
  #         - match: /.*/
  #           to: Personal:Expenses:Unknown
  #
  # For every hash in an array of income and expense rules, you can specify one or more of the following yaml
  # directives. Note that these directives all serve to provide two function: matching input transactions, indicating
  # how to reconcile any matches it captures.
  #
  # ### Income & Expense Rules: Matching
  # The following directives are matching rules. If more than one of these directives are encountered in a rule,
  # they're and'd together. Meaning: all of the conditions that are listed, need to apply to subject, in order for a
  # match to execute.
  # - **match** [Regexp,String] - If a string is provided, compares the :description of the feed transaction against the
  #   value provided, and matches if they're equal. If a regex is provided, matches the
  #   :description of the feed transaction against the regex provided.
  #   If a regex is provided, captures are supported. (see the note below)
  # - **account** [Regexp,String] - This matcher is useful for reconcilers that support the :to field.
  #   (see {RVGP::Reconcilers::JournalReconciler}). If a string is provided, compares the
  #   account :to which a transaction was assigned, to the value provided. And matches if
  #   they're equal. If a regex is provided, matches the account :to which a transaction
  #   was assigned, against the regex provided.
  #   If a regex is provided, captures are supported. (see the note below)
  # - **account_is_not** [String] - This matcher is useful for reconcilers that support the :to field.
  #   (see {RVGP::Reconcilers::JournalReconciler}). This field matches any transaction
  #   whose account :to, does not equal the provided string.
  # - **amount_less_than** [Commodity] - This field compares it's value to the transaction :amount , and matches if
  #   that amount is less than the provided amount.
  # - **amount_greater_than** [Commodity] - This field compares it's value to the transaction :amount , and matches
  #   if that amount is greater than the provided amount.
  # - **amount_equals** [Commodity] - This field compares it's value to the transaction :amount , and matches if
  #   that amount is equal to the provided amount.
  # - **on_date** [Regexp,Date] - If a date is provided, compares the :date of the feed transaction against the value
  #   provided, and matches if they're equal. If a regex is provided, matches the
  #   :date of the feed, converted to a string in the format 'YYYY-MM-DD', against the regex
  #   provided.
  #   If a regex is provided, captures are supported. (see the note below)
  # - **before_date** [Date] - This field compares it's value to the feed transaction :date, and matches if the feed's
  #   :date occurred before the provided :date.
  # - **after_date** [Date] - This field compares it's value to the feed transaction :date, and matches if the feed's
  #   :date occurred after the provided :date.
  # - **from_is_not** [String] - This field matches any transaction whose account :from, does not equal the provided
  #   string.
  #
  # **NOTE** Some matchers which support captures: This is a powerful feature that allows regexp captured values, to
  # substitute in the :to field of the reconciled transaction. Here's an example of how this feature works:
  #
  #       - match: '/^Reservation\: (?<unit>[^ ]+)/'
  #         to: AirBNB:Income:$unit
  # In this example, the text that existed in the "(?<unit>[^ ]+)" section of the 'match' field, is substituted in
  # place of "$unit" in the output journal.
  #
  # ### Income & Expense Rules: Reconciliation
  # The following directives are reconciliation rules. These rules have nothing to do with matching, and instead
  # apply to the outputted transaction for the rule in which they're declared. If more than one of these rules are
  # present - they all apply.
  # - **to** [String] - This field will provide the :to account to reconcile an input transaction against. Be aware
  #   aware of the above note on captures, as this field supports capture variable substitution.
  # - **from** [String] - This field can be used to change the reconciled :from account, to a different account than
  #   the default :from, that was specified in the root of the reconciler yaml.
  # - **tag** [String] - Tag(s) to apply to the reconciled posting.
  # - **to_tag** [String] - Tag(s) to apply to the :to transfer, the first transfer, in the posting
  # - **targets** [Array<Hash>] - For some transactions, multiple transfers need to expand from a single input
  #   transaction. In those cases, :targets is the reconciliation rule you'll want to use.
  #   This field is expected to be an array of Hashes. With, each hash supporting the
  #   following fields:
  #   - **to** [String] - As with the above :to, this field will provide the account to reconcile the transfer to.
  #   - **amount** [Commodity] - The amount to ascribe to this transfer. While the sum of the targets 'should' equal the
  #     input transaction amount, there is no validation performed by RVGP to do so. So, excercize discretion when
  #     manually breaking out input transactions into multiple transfers.
  #   - **complex_commodity** [ComplexCommodity] - A complex commodity to ascribe to this transfer, instead of an
  #     :amount. See {RVGP::Journal::ComplexCommodity.from_s} for more details on this feature.
  #   - **tags** [Array<String>] - An array of tags to assign to this transfer. See {RVGP::Journal::Posting::Tag.from_s}
  #     for more details on tag formatting.
  # - **to_shorthand** [String] - Reconciler Shorthand is a powerful feature that can reduce duplication, and manual
  #   calculations from your reconciler yaml. The value provided here, must correlate with an available reconciler
  #   shorthand, and if so, sends this rule to that shorthand for reconciliation. See the below section for further
  #   details on this feature.
  # - **shorthand_params** [Hash] - This section is specific to the reconciler shorthand that was specified in the
  #   :to_shorthand field. Any of the key/value pairs specified here, are sent to the reconciler shorthand, along
  #   with the rest of the input transaction. And, presumably, these fields will futher direct the reconciliation
  #   of the input transaction.
  #
  # ## Shorthand
  # Additional time-saving syntax is available in the form of 'Shorthand'. This feature is reliable, though,
  # experimental. The point of 'Shorthand' is to provide ruby modules that takes a matched transaction, and
  # automatically expands this transaction in the form of a ruby-defined macro. Currently, there are a handful
  # of such shorthand macros shipped with RVGP. If there's an interest, user-defined shorthand can be supported
  # in the future. The following shorthand classes, are currently provided in RVGP:
  # - {RVGP::Reconcilers::Shorthand::InternationalAtm} - This Shorthand is useful for unrolling a complex International
  #   ATM withdrawal. This shorthand will automatically calculate and allocate fees around the amounnt withdrawn.
  # - {RVGP::Reconcilers::Shorthand::Investment} - Allocate capital gains or losses, given a symbol, amount, and price.
  # - {RVGP::Reconcilers::Shorthand::Mortgage} - This shorthand will automatically allocate the the escrow, principal,
  #   and interest components of a mortage payment, into constituent accounts.
  # See the documentation in each of these classes, for details on what **:shorthand_params** each of these modules
  # supports.
  #
  # ## Special yaml features
  # All of these pysch extensions, are prefixed with two exclamation points, and can be placed in lieu of a value, for
  # some of the fields outlined above.
  # - <b>!!include</b> [String] - Include another yaml file, in place of this directive. The file is expected to be
  #   provided, immediately followed by this declaration (separated by a space). It's common to see this directive
  #   used as a shortcut to shared :format sections. But, these can be used almost anywhere. Here's an example:
  #
  #         ...
  #         from: "Personal:Assets:AcmeBank:Checking"
  #         label: "Personal AcmeBank:Checking (2023)"
  #         format: !!include config/csv-format-acmebank.yml
  #         ...
  # - <b>!!proc</b> [String] - Convert the contents of the text following this directive, into a Proc object. It'
  #   common to see this directive used in the format section of a reconciler yaml. Here's an example:
  #
  #         ...
  #         fields:
  #         date: !!proc >
  #           date = Date.strptime(row[0], '%m/%d/%Y');
  #           date - 1
  #         amount: !!proc row[1]
  #         description: !!proc row[2]
  #         ...
  #   Note that the use of '>' is a yaml feature, that allows multiline strings to compose by way of an indent in
  #   the lines that follow. For one-line '!!proc' declarations, this character is not needed. Additionally, this
  #   means that in most cases, carriage returns are not parsed. As such, you'll want to terminate lines in these
  #   segments, with a semicolon, to achieve the same end.
  #
  # ## Available Implementations
  # Currently, the following reconciller implementations are available. These implementations support all of the
  # above features, and, may implement additional features.
  # - {RVGP::Reconcilers::CsvReconciler} - this reconciler handles input files of type csv
  # - {RVGP::Reconcilers::JournalReconciler} - this reconciler handles input files of type .journal (Pta accounting
  #   files)
  module Reconcilers
    # This reconciler is instantiated for input files of type csv. Additional parameters are supported in the
    # :format section of this reconciler, which are documented in {RVGP::Reconcilers} under the
    # 'CSV specific format parameters' section.
    class CsvReconciler < RVGP::Base::YamlReconciler
      # TODO Let's see where this goes before we document it... I'm not sure what we want this to be
      # yet.
      class CsvRow
        attr_accessor :date, :description, :amount, :effective_date

        def initialize(date: nil, description: nil, amount: nil, effective_date: nil)
          @date = date
          @description = description
          @amount = amount
          @effective_date = effective_date
        end
      end

      def initialize(yaml)
        super

        missing_fields = if input_format
                           if input_format.key?(:fields)
                             %i[date amount description].map do |attr|
                               format('format/fields/%s', attr) unless input_format[:fields].key?(attr)
                             end.compact
                           else
                             ['format/fields']
                           end
                         else
                           ['format']
                         end

        raise MissingFields.new(*missing_fields) unless missing_fields.empty?
      end

      class << self
        include RVGP::Utilities

        # Mostly this is a class method, to make testing easier
        def path_to_rows(path, fields:, encoding: nil, trim_lines: nil, default_currency: nil,
                         skip_lines: nil, filter_contents: nil, csv_headers: nil, invert_amount: false,
                         reverse_order: false)
          contents = File.read path, **(encoding ? { encoding: } : {})

          start_offset = 0
          end_offset = contents.length

          if trim_lines
            trim_lines_regex = string_to_regex trim_lines.to_s
            trim_lines_regex ||= /(?:[^\n]*\n?){0,#{trim_lines}}\Z/m
            match = trim_lines_regex.match contents
            end_offset = match.begin 0 if match
            return String.new if end_offset.zero?
          end

          if skip_lines
            skip_lines_regex = string_to_regex skip_lines.to_s
            skip_lines_regex ||= /(?:[^\n]*\n){0,#{skip_lines}}/m
            match = skip_lines_regex.match contents
            start_offset = match.end 0 if match
          end

          # If our cursors overlapped, that means we're just returning an empty string
          return String.new if end_offset < start_offset

          contents = contents[start_offset..(end_offset - 1)]

          parse_options = csv_headers ? { headers: csv_headers } : {}

          ret = CSV.parse(
            filter_contents&.call({ contents: contents }.merge({ path: })) || contents,
            **parse_options
          ).map do |csv_row|
            # Set the object values, return the reconciled row:
            attrs = fields.collect do |field, formatter|
              # TODO: I think we can stick formatter as a key, if it's a string, or int
              [field.to_sym, formatter.respond_to?(:call) ? formatter.call(row: csv_row) : csv_row[field]]
            end.compact.to_h

            unless attrs[:amount].is_a?(RVGP::Journal::ComplexCommodity) ||
                   attrs[:amount].is_a?(RVGP::Journal::Commodity)
              attrs[:amount] = RVGP::Journal::Commodity.from_symbol_and_amount(default_currency, attrs[:amount])
            end
            attrs[:amount].invert! if invert_amount

            CsvRow.new(**attrs)
          end

          reverse_order ? ret.reverse : ret
        end
      end

      private

      # We actually returned semi-reconciled transactions here. That lets us do
      # some remedial parsing before rule application, as well as reversing the order
      # which, is needed for the to_shorthand to run in sequence.
      def source_postings
        self.class.path_to_rows(input_file, **input_format).map.with_index do |tx, i|
          RVGP::Base::Reconciler::Posting.new(
            i + 1,
            date: tx.date,
            effective_date: tx.effective_date,
            description: tx.description,
            commodity: transform_commodity(tx.amount),
            from: from
          )
        end
      end
    end
  end
end
