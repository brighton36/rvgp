gem 'finance'
require 'finance'

class Finance::Amortization
  def balance=(val)
    @balance = DecNum.new val
  end

	# This was copied out of :
  # https://github.com/marksweston/finance/blob/master/lib/finance/amortization.rb
  # Because bank of america doesn't round the same way...
	def amortize(rate)
		# For the purposes of calculating a payment, the relevant time
		# period is the remaining number of periods in the loan, not
		# necessarily the duration of the rate itself.
		periods = @periods - @period
		amount = Finance::Amortization.payment @balance, rate.monthly, periods

		pmt = Finance::Payment.new(amount, :period => @period)

		rate.duration.to_i.times do
      # NOTE: This is the only change I made:
      #       (well, I also removed the pmt based block.call above)
      if @block then @block.call(@period, self) end

			# Do this first in case the balance is zero already.
			if @balance.zero? then break end

			# Compute and record interest on the outstanding balance.
			int = (@balance * rate.monthly).round(2)

			interest = Finance::Interest.new(int, :period => @period)

			@balance += interest.amount
			@transactions << interest.dup

			# Record payment.  Don't pay more than the outstanding balance.
			if pmt.amount.abs > @balance then pmt.amount = -@balance end
			@transactions << pmt.dup
			@balance += pmt.amount

			@period += 1
		end
	end

end

module RRA::Transformers::Modules
  class Mortgage

    attr_accessor :principal, :rate, :start_at_installment_number, 
      :additional_payments, :amortization, :payee_principal, :payee_interest, 
      :intermediary_account, :currency, :label, :escrow_account,
      :override_payments
    
    def initialize(rule)
      @label = rule[:module_params][:label]
      @currency = rule[:currency] || '$'
      @principal = RRA::Journal::Commodity.from_symbol_and_amount currency,
         rule[:module_params][:principal].to_s
      @rate = rule[:module_params][:rate]
      @payee_principal = rule[:module_params][:payee_principal]
      @payee_interest = rule[:module_params][:payee_interest]
      @intermediary_account = rule[:module_params][:intermediary_account]
      @escrow_account = rule[:module_params][:escrow_account]
      @start_at_installment_number = rule[:module_params][:start_at_installment_number]
      @additional_payments = rule[:module_params][:additional_payments]
      @override_payments = {}
      rule[:module_params][:override_payments].each do |override|
        unless [:at_installment, :interest].all?{|k| override.has_key? k}
          raise StandardError, "Invalid Payment Override : %s" % override 
        end
        
        @override_payments[ override[:at_installment] ] = {
          interest: RRA::Journal::Commodity.from_symbol_and_amount(
            currency, override[:interest])
        }
      end if rule[:module_params].has_key?(:override_payments)

      raise StandardError, "Mortgage at line:%d missing fields" % [
        rule[:line] ] unless [principal, rate, payee_principal, payee_interest,
        intermediary_account, escrow_account, label].all?
      
      fr = Finance::Rate.new rate, :apr, :duration => 360
      @amortization = principal.to_f.amortize(fr) {|period, amortization| 
        additional_payments.each do |ap|
          if period == ap[:before_installment]

            amortization.balance = amortization.balance - DecNum.new(ap[:amount].to_s)
          end
        end if additional_payments
      }

      @installment_i = start_at_installment_number ? 
        (start_at_installment_number - 1) : 0
    end

    def to_tx(from_posting)
      payment = RRA::Journal::Commodity.from_symbol_and_amount(
        currency, amortization.payments[@installment_i]).abs
      interest = RRA::Journal::Commodity.from_symbol_and_amount(
        currency, amortization.interest[@installment_i])

      if @override_payments.has_key? @installment_i
        interest = @override_payments[@installment_i][:interest]
      end

      principal = payment - interest
      escrow = from_posting.commodity.abs - payment
      total = principal+interest+escrow

      @installment_i += 1

      intermediary_opts = {date: from_posting.date, 
        from: intermediary_account, tags: from_posting.tags}
      
      [ RRA::TransformerBase::Posting.new( from_posting.line_number,
        date: from_posting.date, 
          description: from_posting.description, from: from_posting.from, 
          tags: from_posting.tags,
          targets: [to: intermediary_account, commodity: total] ),
        # Principal:
        RRA::TransformerBase::Posting.new( from_posting.line_number,
          intermediary_opts.merge({ 
          description: '%s (#%d) Principal' % [label, (@installment_i-1)],
          targets: [ { to: payee_principal, commodity: principal } ]
        })),
        # Interest:
        RRA::TransformerBase::Posting.new( from_posting.line_number,
          intermediary_opts.merge({ 
          description: '%s (#%d) Interest' % [label, (@installment_i-1)],
          targets: [{ to: payee_interest, commodity: interest}]
        })),
        # Escrow:
        RRA::TransformerBase::Posting.new( from_posting.line_number,
          intermediary_opts.merge({
          description: '%s (#%d) Escrow' % [label, (@installment_i-1)],
          targets: [{ to: escrow_account, commodity: escrow}]
        }))
      ]
    end
  end
end
