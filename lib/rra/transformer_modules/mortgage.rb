# frozen_string_literal: true

gem 'finance'
require 'finance'
require_relative './finance_gem_hacks'

module RRA
  module Transformers
    module Modules
      # This transformer module will automatically allocate the the escrow, principal, and
      # interest components of a mortage debit, into constituent accounts. The amounts of
      # each, are automatically calculated, based on the loan terms, and taking the residual
      # leftover, into a escrow account, presumably for taxes and insurance to be paid by
      # the mortgage provider.
      #
      # The module parameters we support are:
      #  :label - TODO document this
      #  :principal - TODO document this
      #  :rate - TODO document this
      #  :payee_pricipal - TODO document this
      #  :payee_interest - TODO document this
      #  :intermediary_account - TODO document this
      #  :escrow_account - TODO document this
      #  :start_at_installment_number - TODO document this
      #  :additional_payments - TODO document this
      #  :override_payments - TODO document this. note that we expect :at_installment,
      #                       and :interest keys inside each of these
      class Mortgage
        attr_accessor :principal, :rate, :start_at_installment_number,
                      :additional_payments, :amortization, :payee_principal, :payee_interest,
                      :intermediary_account, :currency, :label, :escrow_account, :override_payments

        def initialize(rule)
          @label = rule[:module_params][:label]
          @currency = rule[:currency] || '$'
          @principal = RRA::Journal::Commodity.from_symbol_and_amount currency, rule[:module_params][:principal].to_s
          @rate = rule[:module_params][:rate]
          @payee_principal = rule[:module_params][:payee_principal]
          @payee_interest = rule[:module_params][:payee_interest]
          @intermediary_account = rule[:module_params][:intermediary_account]
          @escrow_account = rule[:module_params][:escrow_account]
          @start_at_installment_number = rule[:module_params][:start_at_installment_number]
          @additional_payments = rule[:module_params][:additional_payments]
          @override_payments = {}
          if rule[:module_params].key? :override_payments
            rule[:module_params][:override_payments].each do |override|
              unless %i[at_installment interest].all? { |k| override.key? k }
                raise StandardError, format('Invalid Payment Override : %s', override)
              end

              @override_payments[ override[:at_installment] ] = {
                interest: RRA::Journal::Commodity.from_symbol_and_amount(currency, override[:interest])
              }
            end
          end

          unless [principal, rate, payee_principal, payee_interest, intermediary_account, escrow_account, label].all?
            raise StandardError, format('Mortgage at line:%d missing fields', rule[:line])
          end

          fr = Finance::Rate.new rate, :apr, duration: 360
          @amortization = principal.to_f.amortize(fr) do |period, amortization|
            additional_payments&.each do |ap|
              if period == ap[:before_installment]
                amortization.balance = amortization.balance - DecNum.new(ap[:amount].to_s)
              end
            end
          end

          @installment_i = start_at_installment_number ? (start_at_installment_number - 1) : 0
        end

        def to_tx(from_posting)
          payment = RRA::Journal::Commodity.from_symbol_and_amount(currency, amortization.payments[@installment_i]).abs
          interest = RRA::Journal::Commodity.from_symbol_and_amount(currency, amortization.interest[@installment_i])

          interest = @override_payments[@installment_i][:interest] if @override_payments.key? @installment_i

          principal = payment - interest
          escrow = from_posting.commodity.abs - payment
          total = principal + interest + escrow

          @installment_i += 1

          intermediary_opts = { date: from_posting.date, from: intermediary_account, tags: from_posting.tags }

          [RRA::TransformerBase::Posting.new(from_posting.line_number,
                                             date: from_posting.date,
                                             description: from_posting.description,
                                             from: from_posting.from,
                                             tags: from_posting.tags,
                                             targets: [to: intermediary_account, commodity: total]),
           # Principal:
           RRA::TransformerBase::Posting.new(
             from_posting.line_number,
             intermediary_opts.merge({ description: format('%<label>s (#%<num>d) Principal',
                                                           label: label,
                                                           num: @installment_i - 1),
                                       targets: [{ to: payee_principal, commodity: principal }] })
           ),

           # Interest:
           RRA::TransformerBase::Posting.new(
             from_posting.line_number,
             intermediary_opts.merge({ description: format('%<label>s (#%<num>d) Interest',
                                                           label: label,
                                                           num: @installment_i - 1),
                                       targets: [{ to: payee_interest, commodity: interest }] })
           ),

           # Escrow:
           RRA::TransformerBase::Posting.new(
             from_posting.line_number,
             intermediary_opts.merge({ description: format('%<label>s (#%<num>d) Escrow',
                                                           label: label,
                                                           num: @installment_i - 1),
                                       targets: [{ to: escrow_account, commodity: escrow }] })
           )]
        end
      end
    end
  end
end
