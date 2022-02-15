module RRA::Transformers::Modules
  class Investment

    attr_reader :tag, :symbol, :price, :amount, :total, :capital_gains,
      :remainder_amount, :remainder_account, :targets, :is_sell,
      :to, :gains_account

    def initialize(rule)
      @tag = rule[:tag]
      @targets = rule[:targets]
      @to = rule[:to] || 'Personal:Assets'

      if rule.has_key? :module_params
        @symbol = rule[:module_params][:symbol]
        @amount = rule[:module_params][:amount]
        @gains_account = rule[:module_params][:gains_account]

        %w(price total capital_gains).each do |key|
          if rule[:module_params].has_key? key.to_sym
            instance_variable_set "@#{key}".to_sym, 
              rule[:module_params][key.to_sym].to_commodity
          end
        end
      end

      raise StandardError, "Investment at line:%s missing fields" % [
        rule[:line].inspect ] unless [symbol, amount].all?

      @is_sell = (amount.to_f <= 0) 

      # I mostly just think this doesn't make any sense... I guess if we took a
      # loss...
      raise StandardError, "Unimplemented" % [rule.inspect
        ] if (capital_gains and !is_sell)

      raise StandardError, "Investment at line:%s missing gains_account" % [
        rule.inspect ] if (gains_account.nil? or capital_gains.nil?) and is_sell

      raise StandardError, "Investment at line:%s missing an price or total" % [
        rule[:line].inspect ] unless total or price

      raise StandardError, "Investment at line:%s specified both price and total" % [
        rule[:line].inspect ] if total and price
    end

    def to_tx(from_posting)
      income_targets = []

      # NOTE: 
      #   I pulled most of this from: https://hledger.org/investments.html
      if is_sell and capital_gains
        # NOTE: I'm not positive about this .abs....
        cost_basis = (total || (price * amount.to_f.abs)) - capital_gains

        income_targets << {to: to, 
          complex_commodity: RRA::Journal::ComplexCommodity.new(
            left: [amount, symbol].join(' ').to_commodity, 
            operation: :per_lot, right: cost_basis)}

        income_targets << {to: gains_account,
           commodity: capital_gains.dup.invert!} if capital_gains
      else
        income_targets << {to: to, 
          complex_commodity: RRA::Journal::ComplexCommodity.new(
            left: [amount, symbol].join(' ').to_commodity, 
            operation: ((price) ? :per_unit : :per_lot), 
            right: ((price) ? price : total)) }
      end

      income_targets += targets.collect{ |t|
        ret = { to: t[:to] }
        ret[:commodity] = RRA::Journal::Commodity.from_symbol_and_amount(
          t[:currency] || '$', t[:amount].to_s ) if t.has_key?(:amount)

        ret[:complex_commodity] = RRA::Journal::ComplexCommodity.from_s(
          t[:complex_commodity] ) if t.has_key? :complex_commodity
        ret
      } if targets

      RRA::TransformerBase::Posting.new from_posting.line_number, 
        date: from_posting.date,
        description: from_posting.description,
        from: from_posting.from,
        tags: from_posting.tags,
        targets: income_targets
    end
  end
end
