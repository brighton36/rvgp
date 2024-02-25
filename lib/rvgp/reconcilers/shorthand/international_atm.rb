# frozen_string_literal: true

module RVGP
  module Reconcilers
    module Shorthand
      # This reconciler module will automatically allocate ATM components of a transaction, to constituent
      # accounts. This module is useful for tracking the myriad expenses that banks impose on your atm
      # withdrawals internationally. This module takes the total withdrawal, as reported in the input file
      # and deducts conversion_markup and operation_costs from that total. It then takes the remainder balance
      # and constructs a {RVGP::Journal::ComplexCommodity} with the provided :amount as the :left side of that
      # balance, and the remainder after fees on the right side. This seems to be how all ATM's (that I've
      # encountered) work. Note that not all atm, use all of the fees listed below. Some will use them all,
      # some will use a subset.
      #
      # The module parameters we support are:
      # - *amount* [Commodity] - The amount you withdrew on the ATM screen. This is paper amount, that you received.
      #   This amount should be denoted in the commodity you received.
      # - *operation_cost* [Commodity] - This amount is denominated in the same currency you received in paper, and
      #   is typically listed in a summary screen, and on your printed receipt.
      # - *conversion_markup* [String] - This is a percentage, expressed as a string. So, "7.5%" would be expected
      #   to be written as "7.5", here. This amount is typically listed on a summary screen, and in your printed
      #   receipt.
      # - *conversion_markup_to* [String] - The account that :conversion_markup fees should be transferred to
      # - *operation_cost_to* [String] - The account that :operation_cost fees should be transferred to
      #
      # = Example
      # Here's how this module might be used in your reconciler:
      #   ...
      #   - match: /BANCOLOMBIA/
      #     to: Personal:Assets:Cash
      #     to_shorthand: InternationalAtm
      #     shorthand_params:
      #       amount: "600000 COP"
      #       operation_cost: "24290.00 COP"
      #       operation_cost_to: Personal:Expenses:Banking:Fees:RandomAtmOperator
      #       conversion_markup: "7.5"
      #       conversion_markup_to: Personal:Expenses:Banking:Fees:RandomAtmOperator
      #   ...
      # And how one of these above uses will reconcile, in your build:
      #   ...
      #   2023-02-18 BANCOLOMBIA AERO_JMC4 antioquia
      #     Personal:Assets:Cash                                600000.00 COP @@ $ 123.26
      #     Personal:Expenses:Banking:Fees:RandomAtmOperator    24290.00 COP @@ $ 4.99
      #     Personal:Expenses:Banking:Fees:RandomAtmOperator    $ 9.62
      #     Personal:Assets:AcmeBank:Checking
      #   ...
      # Note that the reconciler line above, could match more than one transaction in the input file, and if it
      # does, each of them will be expanded similarly to the expansion below. Though, with international exchange
      # rates changing on a daily basis, the numbers may be different, depending on the debit amount encountered
      # in the input file.
      class InternationalAtm
        # @!visibility private
        MSG_MISSING_REQUIRED_FIELDS = "'International Atm' module at line:%s missing required field %s"
        # @!visibility private
        MSG_OPERATION_COST_AND_AMOUNT_MUST_HAVE_SAME_COMMODITY = "'International Atm' module at line:%s requires " \
                                                                 'that the operation cost currency matches the ' \
                                                                 'amount withdrawn'
        # @!visibility private
        MSG_FIELD_REQUIRED_IF_FIELD_EXISTS = "'International Atm' module at line:%s. Field %s is required if field " \
                                             '%s is provided.'

        # @!visibility private
        attr_reader :tag, :targets, :to, :amount, :operation_cost, :conversion_markup,
                    :conversion_markup_to, :operation_cost_to

        # @!visibility private
        def initialize(rule)
          @tag = rule[:tag]
          @targets = rule[:targets]
          @to = rule[:to] || 'Personal:Assets'

          if rule.key? :shorthand_params
            shorthand_params = rule[:shorthand_params]
            @amount = shorthand_params[:amount].to_commodity if shorthand_params.key? :amount
            @operation_cost = shorthand_params[:operation_cost].to_commodity if shorthand_params.key? :operation_cost
            if shorthand_params.key? :conversion_markup
              @conversion_markup = (BigDecimal(shorthand_params[:conversion_markup]) / 100) + 1
            end
            if shorthand_params.key? :conversion_markup_to
              @conversion_markup_to = shorthand_params[:conversion_markup_to]
            end
            @operation_cost_to = shorthand_params[:operation_cost_to] if shorthand_params.key? :operation_cost_to
          end

          raise StandardError, format(MSG_MISSING_REQUIRED_FIELDS, rule[:line].inspect, 'amount') unless amount

          if conversion_markup && conversion_markup_to.nil?
            raise StandardError, format(MSG_MISSING_REQUIRED_FIELDS, rule[:line].inspect, 'conversion_markup_to',
                                        'conversion_markup')
          end

          if operation_cost && operation_cost_to.nil?
            raise StandardError, format(MSG_MISSING_REQUIRED_FIELDS, rule[:line].inspect, 'operation_cost_to',
                                        'operation_cost')
          end

          if operation_cost && operation_cost.alphabetic_code != amount.alphabetic_code
            raise StandardError, format(MSG_OPERATION_COST_AND_AMOUNT_MUST_HAVE_SAME_COMMODITY, rule[:line].inspect)
          end
        end

        # @!visibility private
        def to_tx(from_posting)
          reported_amount = from_posting.commodity
          targets = []

          if conversion_markup
            conversion_markup_fees = (reported_amount - (reported_amount / conversion_markup)).round(
              RVGP::Journal::Currency.from_code_or_symbol(reported_amount.code).minor_unit
            )
            targets << { to: conversion_markup_to, commodity: conversion_markup_fees }
          end

          if operation_cost
            amount_with_operation_cost = amount + operation_cost
            operation_cost_fraction = (
              operation_cost.quantity_as_bigdecimal / amount_with_operation_cost.quantity_as_bigdecimal
            )

            amount_after_conversion_fees = [reported_amount, conversion_markup_fees].compact.reduce(:-)

            operation_cost_fees = (amount_after_conversion_fees * operation_cost_fraction).round(
              RVGP::Journal::Currency.from_code_or_symbol(amount_after_conversion_fees.code).minor_unit
            )
            targets << { to: operation_cost_to,
                         complex_commodity: RVGP::Journal::ComplexCommodity.new(left: operation_cost,
                                                                               operation: :per_lot,
                                                                               right: operation_cost_fees) }
          end

          remitted = [reported_amount, conversion_markup_fees, operation_cost_fees].compact.reduce(:-)

          targets << { to: to,
                       complex_commodity: RVGP::Journal::ComplexCommodity.new(left: amount,
                                                                             operation: :per_lot,
                                                                             right: remitted) }

          RVGP::Base::Reconciler::Posting.new from_posting.line_number,
                                             date: from_posting.date,
                                             description: from_posting.description,
                                             from: from_posting.from,
                                             tags: from_posting.tags,
                                             targets: targets.reverse
        end
      end
    end
  end
end
