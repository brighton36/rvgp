# frozen_string_literal: true

module RVGP
  module Reconcilers
    module Shorthand
      # This reconciler shorthand will transcribe an additonal pair of transfers, whose amount matches the matched
      # transaction
      #
      # The shorthand parameters we support are:
      # - **additional_to** [String] - This is the account which will be used for the credit transfer
      # - **additional_from** [String] - This is the account which will be used for the debit transfer
      #
      # # Example
      # Here's how this shorthand might be used in your reconciler:
      # ```
      # ...
      # - match: /AcmeFinance Payments/
      #   # ...
      #   to_shorthand: DoublePost
      #   shorthand_params:
      #     additional_from: Transfers:PersonalChecking_VendorChecking
      #     additional_to: Personal:Liabilities:VendorReimbursal
      # ...
      class DoublePost
        # @!visibility private
        attr_reader :tag, :targets, :to, :amount, :additional_to, :additional_from

        # @!visibility private
        def initialize(rule)
          @tag = rule[:tag]
          @targets = rule[:targets]
          @to = rule[:to] || 'Personal:Assets'

          if rule.key? :shorthand_params
            shorthand_params = rule[:shorthand_params]
            @additional_to = shorthand_params[:additional_to] if shorthand_params.key? :additional_to
            @additional_from = shorthand_params[:additional_from] if shorthand_params.key? :additional_from
          end
        end

        # @!visibility private
        def to_tx(from_posting)
          reported_amount = from_posting.commodity
          targets = []

          # First target:
          targets << { to: to, commodity: reported_amount, effective_date: from_posting.effective_date }

          # Additional Target
          targets << { to: additional_to, commodity: reported_amount } if additional_to
          targets << { to: additional_from, commodity: reported_amount.dup.invert! } if additional_from

          # Additional target:
          RVGP::Base::Reconciler::Posting.new from_posting.line_number,
                                              date: from_posting.date,
                                              description: from_posting.description,
                                              from: from_posting.from,
                                              tags: from_posting.tags,
                                              targets: targets
        end
      end
    end
  end
end
