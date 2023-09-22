# frozen_string_literal: true

module RRA
  module Transformers
    module Modules
      # This transformer module will automatically allocate ATM components of an expense, to a specified
      # account. (Presumably, 'Personal:Assets:Cash'). The remainder balance, after this allocation,
      # will be allocated by way of the normal rules that apply to any transaction.
      #
      # The module parameters we support are:
      #  :amount - TODO document this
      #  :operation_cost - TODO document this
      #  :conversion_markup - TODO document this
      #  :conversion_markup_to - TODO document this
      #  :operation_cost_to - TODO document this
      class InternationalAtm
        MSG_MISSING_REQUIRED_FIELDS = "'International Atm' module at line:%s missing required field %s"
        MSG_OPERATION_COST_AND_AMOUNT_MUST_HAVE_SAME_COMMODITY = "'International Atm' module at line:%s requires " \
                                                                 'that the operation cost currency matches the ' \
                                                                 'amount withdrawn'
        MSG_FIELD_REQUIRED_IF_FIELD_EXISTS = "'International Atm' module at line:%s. Field %s is required if field " \
                                             '%s is provided.'

        attr_reader :tag, :targets, :to, :amount, :operation_cost, :conversion_markup,
                    :conversion_markup_to, :operation_cost_to

        def initialize(rule)
          @tag = rule[:tag]
          @targets = rule[:targets]
          @to = rule[:to] || 'Personal:Assets'

          if rule.key? :module_params
            module_params = rule[:module_params]
            @amount = module_params[:amount].to_commodity if module_params.key? :amount
            @operation_cost = module_params[:operation_cost].to_commodity if module_params.key? :operation_cost
            if module_params.key? :conversion_markup
              @conversion_markup = (BigDecimal(module_params[:conversion_markup]) / 100) + 1
            end
            @conversion_markup_to = module_params[:conversion_markup_to] if module_params.key? :conversion_markup_to
            @operation_cost_to = module_params[:operation_cost_to] if module_params.key? :operation_cost_to
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

        def to_tx(from_posting)
          reported_amount = from_posting.commodity
          targets = []

          if conversion_markup
            conversion_markup_fees = (reported_amount - (reported_amount / conversion_markup)).round(
              RRA::Journal::Currency.from_code_or_symbol(reported_amount.code).minor_unit
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
              RRA::Journal::Currency.from_code_or_symbol(amount_after_conversion_fees.code).minor_unit
            )
            targets << { to: operation_cost_to,
                         complex_commodity: RRA::Journal::ComplexCommodity.new(left: operation_cost,
                                                                               operation: :per_lot,
                                                                               right: operation_cost_fees) }
          end

          remitted = [reported_amount, conversion_markup_fees, operation_cost_fees].compact.reduce(:-)

          targets << { to: to,
                       complex_commodity: RRA::Journal::ComplexCommodity.new(left: amount,
                                                                             operation: :per_lot,
                                                                             right: remitted) }

          RRA::Base::Transformer::Posting.new from_posting.line_number,
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
