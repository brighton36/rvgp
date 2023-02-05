require_relative 'utilities'

module RRA
  class TransformerBase
    include RRA::Utilities

    class MissingFields < StandardError
      def initialize(*args)
        super "One or more required keys %s, were missing in the yaml" % 
          args.collect(&:inspect).join(', ')
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
        @date, @description, @commodity, @complex_commodity, @from, @to, @tags, 
          @targets = opts[:date], opts[:description], opts[:commodity], 
          opts[:complex_commodity], opts[:from], opts[:to], (opts[:tags] || []),
          opts[:targets] || []
      end

      def to_journal_posting
        RRA::Journal::Posting.new date, description, 
          tags: (tags) ? tags.collect(&:to_tag) : nil,
          transfers: targets.collect{|target| 
            RRA::Journal::Posting::Transfer.new target[:to], 
              commodity: target[:commodity], 
              complex_commodity: target[:complex_commodity], 
              tags: (target[:tags]) ? target[:tags].collect(&:to_tag) : nil
          }+[RRA::Journal::Posting::Transfer.new(from)]
      end
    end

    attr_reader :label, :file, :output_file, :input_file, :starts_on, :balances,
      :disable_checks
    attr_reader :from, :income_rules, :expense_rules, :tag_accounts, 
      :cash_back, :cash_back_to, :reverse_order, :default_currency

    HEADER = "; -*- %s -*-¬\n; vim: syntax=ledger"

    REQUIRED_FIELDS = %w(label output input from income expense).collect(&:to_sym)

    # NOTE: yaml is expected to be an RRA::Yaml
    def initialize(yaml)
      @label, @file, @dependencies = yaml[:label], yaml.path, yaml.dependencies
      @starts_on = (yaml.has_key?(:starts_on)) ? 
        Date.strptime(yaml[:starts_on], '%Y-%m-%d') : nil

      missing_fields = REQUIRED_FIELDS.find_all{|attr| !yaml.has_key? attr}
      raise MissingFields.new(*missing_fields) if missing_fields.length > 0

      @output_file = RRA.app.config.build_path 'journals/%s' % yaml[:output]
      @input_file = RRA.app.config.project_path 'feeds/%s' % yaml[:input]

      @from = yaml[:from]
      @income_rules = yaml[:income]
      @expense_rules = yaml[:expense]
      @default_currency = yaml[:default_currency] || '$'
      @transform_commodities = yaml[:transform_commodities] || {}
      @balances = yaml[:balances]
      @disable_checks = (yaml.has_key? :disable_checks) ? 
         yaml[:disable_checks].collect(&:to_sym) : []

      if yaml.has_key? :tag_accounts
        @tag_accounts = yaml[:tag_accounts]
        raise StandardError, "One or more tag_accounts entries is missing an "+
          ":account or :tag key" unless @tag_accounts.all?{ |ta|
          [:account, :tag].all?{|k| ta.has_key? k} }
      end

      if yaml.has_key? :format
        if yaml[:format].has_key? :reverse_order
          @reverse_order = yaml[:format][:reverse_order]
        end

        if yaml[:format].has_key?(:cash_back)
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
      ( as_taskname == str || from == str || label == str || 
        file == str_as_file || input_file == str_as_file || 
        output_file == str_as_file )
    end

    def dependencies
      [file, input_file]+@dependencies
    end

    def uptodate?
      FileUtils.uptodate? output_file, dependencies
    end

    # This file is used to mtime the last success 
    def validated_touch_file_path
      '%s.valid' % output_file
    end

    def mark_validated!
      FileUtils.touch validated_touch_file_path 
    end

    def validated?
      FileUtils.uptodate? validated_touch_file_path, [ output_file ]
    end

    def transform_commodity(from)
      # NOTE: We could be dealing with a ComplexCommodity, hence the check
      # for a .code
      if from.respond_to?(:code) and @transform_commodities.has_key?(from.code.to_sym)
        # NOTE: Maybe we need to Create a new Journal::Commodity, so that the 
        # alphacode reloads?
        from.code = @transform_commodities[from.code.to_sym]
      end

      from
    end

    def transform_posting(rule, posting)
      # NOTE: The modules produce more than one tx per csv line, sometimes:

      to = rule[:to].dup
      posting.from = rule[:from] if rule.has_key? :from

      posting.tags << rule[:tag] if rule.has_key? :tag

      # Let's do a find and replace on the :to if we have anything captured
      # This is kind of rudimentary, and only supports named_caputers atm
      # but I think it's fine for now. Probably it's broken wrt cash back or
      # something...
      to.scan(/\$([0-9a-z]+)/i).each do |substitutes|
        substitutes.each do |substitute|
          replace = rule[:captures][substitute]
          to.sub! '$%s' % substitute, replace if replace
        end
      end if rule[:captures]

      if rule.has_key? :to_module
        rule_key = (posting.commodity.positive?) ? :expense : :income

        @modules ||= {}
        @modules[rule_key] ||= {}
        mod = @modules[rule_key][rule[:index]]

        unless mod
          module_klass = 'RRA::Transformers::Modules::%s' % rule[:to_module]

          unless Object.const_defined?(module_klass)
            raise StandardError, "Unknown module %s" % module_klass 
          end

          mod = Object.const_get(module_klass).new rule

          @modules[rule_key][rule[:index]] = mod
        end

        mod.to_tx posting
      elsif rule.has_key?(:targets)
        # NOTE: I guess we don't support cashback when multiple targets are
        # specified ATM
        if cash_back && cash_back.match(posting.description)
          # If it turns out we need this feature in the future, I guess, 
          # implement it?
          raise StandardError, "Unimplemented." 
        end

        posting.targets = rule[:targets].collect{ |rule_target|
          if rule_target.has_key? :currency
            commodity = RRA::Journal::Commodity.from_symbol_and_amount(
              rule_target[:currency] || default_currency, 
              rule_target[:amount].to_s)
          elsif rule_target.has_key? :complex_commodity
            complex_commodity = RRA::Journal::ComplexCommodity.from_s(
              rule_target[:complex_commodity])
          else
            commodity = rule_target[:amount].to_s.to_commodity
          end

          {to: rule_target[:to], commodity: commodity, 
           complex_commodity: complex_commodity, tags: rule_target[:tags]}
        }

        posting
      else
        # We unroll some of the allocation in here, since (I think) the logic 
        # relating to cash backs and such are in 'the bank' and not 'the transaction'
        residual_commodity = posting.commodity

        if cash_back and cash_back.match(posting.description)
          cash_back_commodity = RRA::Journal::Commodity.from_symbol_and_amount $1, $2
          residual_commodity -= cash_back_commodity
          posting.targets << {to: cash_back_to, commodity: cash_back_commodity}
        end

        posting.targets << {to: to, commodity: residual_commodity}

        posting
      end
    end

    def postings
      @postings ||= source_postings.tap{|posts| 
        # If appropriate, reverse the order:
        posts.reverse! if reverse_order
      }.collect{|posting| 
        # See what rule applies to this posting:
        rule = match_rule( 
          (posting.commodity.positive?) ? expense_rules : income_rules, posting )

        # Transform the posting, according to that rule:
        transform_posting rule, posting
      }.compact.flatten.collect{|posting|
        # tag_accounts ...
        tag_accounts.each do |tag_rule|
          # Note that we're operating under a kind of target model here, where
          # the posting itself isnt tagged, but the targets of the posting are.
          # This is a bit different than the transform_posting
          posting.targets.each do |target|
            # NOTE: This section should possibly DRY up with the 
            # transform_posting() method
            if tag_rule.has_key? :account_is_not
              account_isnt_regex = string_to_regex tag_rule[:account_is_not]
              next if (account_isnt_regex) ?
                account_isnt_regex.match(target[:to]) : 
                (tag_rule[:account_is_not] == target[:to])
            end

            if tag_rule.has_key? :from_is_not
              from_isnt_regex = string_to_regex tag_rule[:from_is_not]
              next if (from_isnt_regex) ?
                from_isnt_regex.match(posting.from) : 
                (tag_rule[:from_is_not] == posting.from)
            end

            if tag_rule.has_key? :from
              from_regex = string_to_regex tag_rule[:from]
              next if (from_regex) ? from_regex.match(posting.from).nil? :
                (tag_rule[:from] != posting.from) 
            end

            if tag_rule.has_key? :account
              account_regex = string_to_regex tag_rule[:account]
              next if (account_regex) ? account_regex.match(target[:to]).nil? :
                (tag_rule[:account] != target[:to]) 
            end

            target[:tags] ||= []
            target[:tags] << tag_rule[:tag] 
          end
        end if tag_accounts

        # And now we can convert it to the journal posting format
        ret = posting.to_journal_posting

        # NOTE: Might want to return a row number here if it ever triggers:
        raise "Invalid Transaction found %s" % ret.inspect unless ret.valid?
        
        # Cull only the transactions after the specified date:
        (starts_on && ret.date < starts_on) ? nil : ret
      }.compact
    end

    def match_rule(rules, posting)
      rules.each_with_index do |rule, i|
        captures = nil
        if rule.has_key? :match
          match_regex = string_to_regex rule[:match]

          # Not crazy about the nested ifs here, but it seems this is the best
          # we can do:
          if match_regex 
            next if !match_regex.match(posting.description) 
          else
            next if rule[:match] != posting.description
          end

          captures = $~.named_captures.dup if $~ && $~.length > 1
        end

        # :account was added when we added journal_transform
        if rule.has_key? :account
          match_regex = string_to_regex rule[:account]

          # Not crazy about the nested ifs here, but it seems this is the best
          # we can do:
          if match_regex 
            next if !match_regex.match(posting.to) 
          else
            next if rule[:account] != posting.to
          end

          captures = $~.named_captures.dup if $~ && $~.length > 1
        end

        if rule.has_key? :amount_less_than
          amount_less_than = rule[:amount_less_than].to_s.to_commodity

          next if ( 
            (posting.commodity.alphabetic_code != amount_less_than.alphabetic_code ) ||
            (posting.commodity.abs >= amount_less_than ) )
        end

        if rule.has_key? :amount_equals
          amount_equals = rule[:amount_equals].to_s.to_commodity

          next if ( 
            ( posting.commodity.alphabetic_code != amount_equals.alphabetic_code ) ||
            ( posting.commodity.abs != rule[:amount_equals].to_s.to_commodity) )
        end

        if rule.has_key? :on_date
          date_regex = string_to_regex rule[:on_date].to_s

          if date_regex
            next if !date_regex.match(posting.date.strftime('%Y-%m-%d'))
          else
            next if posting.date != rule[:on_date]
          end
        end

        if rule.has_key? :before_date
          next if posting.date >= rule[:before_date]
        end

        if rule.has_key? :after_date
          next if posting.date < rule[:after_date]
        end

        # Success, there was a match:
        return rule.merge(index: i, captures: captures)
      end

      return nil
    end

    def to_ledger
      [ HEADER % label, postings.collect(&:to_ledger),
        ""].flatten.join("\n\n")
    end
    
    def to_ledger!
      File.open(output_file, 'w') { |f| f.write to_ledger }
    end

    def self.all(directory_path)
      # NOTE: I'm not crazy about this method. Probably we should have 
      # implemented a single Transformer class, with CSV/Journal drivers.
      # Nonetheless, this code works for now. Maybe if we add another 
      # driver, we can renovate it, and add some kind of registry for drivers.

      Dir.glob("%s/transformers/*.yml" % directory_path).collect{|path|
        yaml = RRA::Yaml.new path, RRA.app.config.project_path

        raise MissingFields.new :input unless yaml.has_key? :input

        # We could probably make this a registry, though, I'd like to support
        # web addresses eventually. So, probably this designe pattern would
        # have to just be reconsidered entirely around that time.
        case File.extname(yaml[:input])
          when '.csv' then RRA::Transformers::CsvTransformer.new(yaml)
          when '.journal' then RRA::Transformers::JournalTransformer.new(yaml)
          else
            raise StandardError, 
              "Unrecognized file extension for input file \"%s\"" % yaml[:input]
        end
      }
    end
  end
end
