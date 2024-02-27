# frozen_string_literal: true

gem 'finance'
require 'finance'
require_relative './finance_gem_hacks'

module RVGP
  module Reconcilers
    module Shorthand
      # This reconciler module will automatically allocate the the escrow, principal, and interest components of a
      # mortage debit, into constituent accounts. The amounts of each, are automatically calculated, based on the loan
      # terms, and taking the residual leftover, into a escrow account, presumably for taxes and insurance to be paid by
      # the mortgage provider.
      #
      # Its important to note, that a single reconciler rule will match every mortgage payment encountered. And, that
      # each of these payments will generate four transactions in the output file:
      # - The initial payment, which, will be transferred to an :intermediary_account
      # - A principal payment, which, will be debited from the :intermediary account, to the :payee_principal
      # - An interest payment, which, will be debited from the :intermediary account, to the :payee_interest
      # - An escrow payment, which, will be debited from the :intermediary account, to the :escrow_account
      # You can see details of this expansion under the example section below.
      #
      # With regards to the :escrow_account, It's likely that you'll want to either (choose one):
      # - Manually transcribe debits from the escrow account, to escrow payees, in your project's
      #   ./journal/property-name-escrow.journal, based on when your mortgage provider alerts you to these payments.
      # - Download a csv from your mortgage provider, of your escrow account (if they offer one), and define a
      #   reconciler to allocate escrow payments.
      #
      # The module parameters we support are:
      # - **label** [String] - This is a prefix, used in the description of Principal, Interest, and Escrow transactions
      # - **principal** [Commodity] - The mortgage principal
      # - **rate** [Float] - The mortgage rate
      # - **payee_principal** [String] - The account to ascribe principal payments to
      # - **payee_interest** [String] - The account to ascribe interest payments to
      # - **escrow_account** [String] - Te account to ascribe escrow payments to
      # - **intermediary_account** [String] - The account to ascribe intermediary payments to, from the source account,
      #   before being assigned to principal, interest, and escrow break-outs.
      # - **start_at_installment_number** [Integer] - The installment number, of the first matching transaction,
      #   encountered by this module. Year one of a mortgage would start at zero. Subsequent annual reconcilers would
      #   be expected to define an installment number from which calculations can automatically pick-up the work
      #   from years prior.
      # - **additional_payments** [Array<Hash>] - Any additional payments, to apply to the principal, can be listed
      #   here. This field is expected to be an array of hashes, which, are composed of the following fields:
      #   - **before_installment** [Integer] - The payment number, before which, this :amount should apply
      #   - **amount** [Float] - A float that will be deducted from the principal. No commodity is necessary to
      #     delineate, as we assume the same commodity as the :principle.
      # - **override_payments** [Array<Hash>] - I can't explain why this is necessary. But, it seems that the interest
      #   calculations used by some mortgage providers ... aren't accurate. This happened to me, at least. The
      #   calculation being used was off by a penny, on a single installment. And, I didn't care enough to call the
      #   institution and figure out why. So, I added this feature, to allow an override of the automatic calculation,
      #   with the amount provided. This field is expected to be an array of hashes, which are composed of the following
      #   fields:
      #   - **at_installment** [Integer] - The payment number to assert the :interest value.
      #   - **interest** [Float] - The amount of the interest calculation. No commodity is neccessary to delineate, as
      #     we assume the same commodity as the :principle.
      #
      # # Example
      # Here's how this module might be used in your reconciler:
      # ```
      # ...
      # - match: /AcmeFinance Servicing/
      #   to_shorthand: Mortgage
      #   shorthand_params:
      #     label: 1-8-1 Yurakucho Dori Mortgage
      #     intermediary_account: Personal:Expenses:Banking:MortgagePayment:181Yurakucho
      #     payee_principal: Personal:Liabilities:Mortgage:181Yurakucho
      #     payee_interest: Personal:Expenses:Banking:Interest:181Yurakucho
      #     escrow_account: Personal:Assets:AcmeFinance:181YurakuchoEscrow
      #     principal: 260000.00
      #     rate: 0.0499
      #     start_at_installment_number: 62
      # ...
      # ```
      # And here's how that will reconcile one of your payments, in your build:
      # ```
      # ...
      # 2023-01-03 AcmeFinance Servicing MTG PYMT 012345 Yukihiro Matsumoto
      #   Personal:Expenses:Banking:MortgagePayment:181Yurakucho    $ 3093.67
      #   Personal:Assets:AcmeBank:Checking
      #
      # 2023-01-03 1-8-1 Yurakucho Dori Mortgage (#61) Principal
      #   Personal:Liabilities:Mortgage:181Yurakucho    $ 403.14
      #   Personal:Expenses:Banking:MortgagePayment:181Yurakucho
      #
      # 2023-01-03 1-8-1 Yurakucho Dori Mortgage (#61) Interest
      #   Personal:Expenses:Banking:Interest:181Yurakucho    $ 991.01
      #   Personal:Expenses:Banking:MortgagePayment:181Yurakucho
      #
      # 2023-01-03 1-8-1 Yurakucho Dori Mortgage (#61) Escrow
      #   Personal:Assets:AcmeFinance:181YurakuchoEscrow    $ 1699.52
      #   Personal:Expenses:Banking:MortgagePayment:181Yurakucho
      # ...
      # ```
      # Note that you'll have an automatically calculated reconcilation for each payment you
      # make, during the year. A single reconciler rule, will take care of reconciling every
      # payment, automatically.
      class Mortgage
        # @!visibility private
        attr_accessor :principal, :rate, :start_at_installment_number,
                      :additional_payments, :amortization, :payee_principal, :payee_interest,
                      :intermediary_account, :currency, :label, :escrow_account, :override_payments

        # @!visibility private
        def initialize(rule)
          @label = rule[:shorthand_params][:label]
          @currency = rule[:currency] || '$'
          @principal = rule[:shorthand_params][:principal].to_commodity
          @rate = rule[:shorthand_params][:rate]
          @payee_principal = rule[:shorthand_params][:payee_principal]
          @payee_interest = rule[:shorthand_params][:payee_interest]
          @intermediary_account = rule[:shorthand_params][:intermediary_account]
          @escrow_account = rule[:shorthand_params][:escrow_account]
          @start_at_installment_number = rule[:shorthand_params][:start_at_installment_number]
          @additional_payments = rule[:shorthand_params][:additional_payments]
          @override_payments = {}
          if rule[:shorthand_params].key? :override_payments
            rule[:shorthand_params][:override_payments].each do |override|
              unless %i[at_installment interest].all? { |k| override.key? k }
                raise StandardError, format('Invalid Payment Override : %s', override)
              end

              @override_payments[ override[:at_installment] ] = {
                interest: RVGP::Journal::Commodity.from_symbol_and_amount(currency, override[:interest])
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

        # @!visibility private
        def to_tx(from_posting)
          payment = RVGP::Journal::Commodity.from_symbol_and_amount(currency, amortization.payments[@installment_i]).abs
          interest = RVGP::Journal::Commodity.from_symbol_and_amount(currency, amortization.interest[@installment_i])

          interest = @override_payments[@installment_i][:interest] if @override_payments.key? @installment_i

          principal = payment - interest
          escrow = from_posting.commodity.abs - payment
          total = principal + interest + escrow

          @installment_i += 1

          intermediary_opts = { date: from_posting.date, from: intermediary_account, tags: from_posting.tags }

          [RVGP::Base::Reconciler::Posting.new(from_posting.line_number,
                                               date: from_posting.date,
                                               description: from_posting.description,
                                               from: from_posting.from,
                                               tags: from_posting.tags,
                                               targets: [to: intermediary_account, commodity: total]),
           # Principal:
           RVGP::Base::Reconciler::Posting.new(
             from_posting.line_number,
             intermediary_opts.merge({ description: format('%<label>s (#%<num>d) Principal',
                                                           label: label,
                                                           num: @installment_i - 1),
                                       targets: [{ to: payee_principal, commodity: principal }] })
           ),

           # Interest:
           RVGP::Base::Reconciler::Posting.new(
             from_posting.line_number,
             intermediary_opts.merge({ description: format('%<label>s (#%<num>d) Interest',
                                                           label: label,
                                                           num: @installment_i - 1),
                                       targets: [{ to: payee_interest, commodity: interest }] })
           ),

           # Escrow:
           RVGP::Base::Reconciler::Posting.new(
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
