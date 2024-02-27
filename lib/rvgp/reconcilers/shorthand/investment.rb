# frozen_string_literal: true

module RVGP
  module Reconcilers
    # This module contains the built-in Shorthand classes that ship with RVGP. For more details on this
    # feature, see the 'Shorthand' section of the {RVGP::Reconcilers} module.
    module Shorthand
      # This reconciler module will automatically allocate the proceeds (or losses) from a stock sale.
      # This module will allocate capital gains or losses, given a symbol, amount, and price.
      #
      # The module parameters we support are:
      # - **symbol** [String] -  A commodity or currency code, that represents the purchased asset
      # - **amount** [Integer] - The amount of :symbol that was purchased, or if negative, sold.
      # - **price** [Commodity] - A unit price, for the symbol. This field should be delimited if :total is omitted.
      # - **total** [Commodity] - A lot price, the symbol. This represents the net  purchase price, which, would be
      #   divided by the amount, in order to arrive at a unit price. This field should be delimited if :price is
      #   omitted.
      # - **capital_gains** [Commodity] - The amount of the total, to allocate to a capital gains account. Presumably
      #   for tax reporting.
      # - **gains_account** [String] - The account name to allocate capital gains to.
      #
      # # Example
      # Here's how this module might be used in your reconciler:
      # ```
      # ...
      # - match: /Acme Stonk Exchange/
      #   to_shorthand: Investment
      #   shorthand_params:
      #     symbol: VOO
      #     price: "$ 400.00"
      #     amount: "-1000"
      #     capital_gains: "$ -100000.00"
      #     gains_account: Personal:Income:AcmeExchange:VOO
      # ...
      # ```
      # And here's how that will reconcile, in your build:
      # ```
      # ...
      # 2023-06-01 Acme Stonk Exchange ACH CREDIT 123456 Yukihiro Matsumoto
      #   Personal:Assets                   -1000 VOO @@ $ 400000.00
      #   Personal:Income:AcmeExchange:VOO    $ 100000.00
      #   Personal:Assets:AcmeChecking
      #   ...
      # ```
      #
      class Investment
        # @!visibility private
        attr_reader :tag, :symbol, :price, :amount, :total, :capital_gains,
                    :remainder_amount, :remainder_account, :targets, :is_sell,
                    :to, :gains_account

        def initialize(rule)
          @tag = rule[:tag]
          @targets = rule[:targets]
          @to = rule[:to] || 'Personal:Assets'

          if rule.key? :shorthand_params
            @symbol = rule[:shorthand_params][:symbol]
            @amount = rule[:shorthand_params][:amount]
            @gains_account = rule[:shorthand_params][:gains_account]

            %w[price total capital_gains].each do |key|
              if rule[:shorthand_params].key? key.to_sym
                instance_variable_set "@#{key}".to_sym, rule[:shorthand_params][key.to_sym].to_commodity
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

        # @!visibility private
        def to_tx(from_posting)
          income_targets = []

          # NOTE: I pulled most of this from: https://hledger.org/investments.html
          if is_sell && capital_gains
            # NOTE: I'm not positive about this .abs....
            cost_basis = (total || (price * amount.to_f.abs)) - capital_gains

            income_targets << { to: to,
                                complex_commodity: RVGP::Journal::ComplexCommodity.new(
                                  left: [amount, symbol].join(' ').to_commodity,
                                  operation: :per_lot,
                                  right: cost_basis
                                ) }

            income_targets << { to: gains_account, commodity: capital_gains.dup.invert! } if capital_gains
          else
            income_targets << { to: to,
                                complex_commodity: RVGP::Journal::ComplexCommodity.new(
                                  left: [amount, symbol].join(' ').to_commodity,
                                  operation: (price ? :per_unit : :per_lot),
                                  right: price || total
                                ) }
          end

          if targets
            income_targets += targets.map do |t|
              ret = { to: t[:to] }
              if t.key? :amount
                # TODO: I think there's a bug here, in that amounts with commodities, won't parse...
                ret[:commodity] = RVGP::Journal::Commodity.from_symbol_and_amount t[:currency] || '$', t[:amount].to_s
              end

              if t.key? :complex_commodity
                ret[:complex_commodity] = RVGP::Journal::ComplexCommodity.from_s t[:complex_commodity]
              end

              ret
            end
          end

          RVGP::Base::Reconciler::Posting.new from_posting.line_number,
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
