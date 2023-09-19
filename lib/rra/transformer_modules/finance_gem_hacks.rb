# frozen_string_literal: true

module Finance
  # The default functionality in this class, specified in the finance gem, is
  # overwritten, to support the additional_payments feature of RRA::Transformers::Modules::Mortgage
  class Amortization
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

      pmt = Finance::Payment.new amount, period: @period

      rate.duration.to_i.times do
        # NOTE: This is the only change I made:
        #       (well, I also removed the pmt based block.call above)
        @block&.call(@period, self)

        # Do this first in case the balance is zero already.
        break if @balance.zero?

        # Compute and record interest on the outstanding balance.
        int = (@balance * rate.monthly).round(2)

        interest = Finance::Interest.new int, period: @period

        @balance += interest.amount
        @transactions << interest.dup

        # Record payment.  Don't pay more than the outstanding balance.
        pmt.amount = -@balance if pmt.amount.abs > @balance
        @transactions << pmt.dup
        @balance += pmt.amount

        @period += 1
      end
    end
  end
end
