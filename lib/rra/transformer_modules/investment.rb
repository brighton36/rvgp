# frozen_string_literal: true

module RRA
  module Transformers
    module Modules
      # This transformer module will automatically allocate the proceeds (or lack thereof) from a stock sale.
      # This module will allocate capital gains or losses, given a symbol, amount, and price.
      #
      # The module parameters we support are:
      #  :symbol - TODO document this
      #  :amount - TODO document this
      #  :gains_account - TODO document this
      #  :price - TODO document this
      #  :total - TODO document this
      #  :capital_gains - TODO document this
      class Investment
        attr_reader :tag, :symbol, :price, :amount, :total, :capital_gains,
                    :remainder_amount, :remainder_account, :targets, :is_sell,
                    :to, :gains_account

        def initialize(rule)
          @tag = rule[:tag]
          @targets = rule[:targets]
          @to = rule[:to] || 'Personal:Assets'

          if rule.key? :module_params
            @symbol = rule[:module_params][:symbol]
            @amount = rule[:module_params][:amount]
            @gains_account = rule[:module_params][:gains_account]

            %w[price total capital_gains].each do |key|
              if rule[:module_params].key? key.to_sym
                instance_variable_set "@#{key}".to_sym, rule[:module_params][key.to_sym].to_commodity
              end
            end
          end

          unless [symbol, amount].all?
            raise StandardError, format('Investment at line:%s missing fields', rule[:line].inspect)
          end

          @is_sell = (amount.to_f <= 0)

          # I mostly just think this doesn't make any sense... I guess if we took a
          # loss...
          raise StandardError, format('Unimplemented %s', rule.inspect) if capital_gains && !is_sell

          if (gains_account.nil? || capital_gains.nil?) && is_sell
            raise StandardError, format('Investment at line:%s missing gains_account', rule.inspect)
          end

          unless total || price
            raise StandardError, format('Investment at line:%s missing an price or total', rule[:line].inspect)
          end

          if total && price
            raise StandardError, format('Investment at line:%s specified both price and total', rule[:line].inspect)
          end
        end

        def to_tx(from_posting)
          income_targets = []

          # NOTE: I pulled most of this from: https://hledger.org/investments.html
          if is_sell && capital_gains
            # NOTE: I'm not positive about this .abs....
            cost_basis = (total || (price * amount.to_f.abs)) - capital_gains

            income_targets << { to: to,
                                complex_commodity: RRA::Journal::ComplexCommodity.new(
                                  left: [amount, symbol].join(' ').to_commodity,
                                  operation: :per_lot,
                                  right: cost_basis
                                ) }

            income_targets << { to: gains_account, commodity: capital_gains.dup.invert! } if capital_gains
          else
            income_targets << { to: to,
                                complex_commodity: RRA::Journal::ComplexCommodity.new(
                                  left: [amount, symbol].join(' ').to_commodity,
                                  operation: (price ? :per_unit : :per_lot),
                                  right: price || total
                                ) }
          end

          if targets
            income_targets += targets.map do |t|
              ret = { to: t[:to] }
              if t.key? :amount
                ret[:commodity] = RRA::Journal::Commodity.from_symbol_and_amount t[:currency] || '$', t[:amount].to_s
              end

              if t.key? :complex_commodity
                ret[:complex_commodity] = RRA::Journal::ComplexCommodity.from_s t[:complex_commodity]
              end

              ret
            end
          end

          RRA::Base::Transformer::Posting.new from_posting.line_number,
                                              date: from_posting.date,
                                              description: from_posting.description,
                                              from: from_posting.from,
                                              tags: from_posting.tags,
                                              targets: income_targets
        end
      end
    end
  end
end
