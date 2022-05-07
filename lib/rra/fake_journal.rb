require_relative 'journal'
require_relative 'journal/commodity'

# NOTE: I'm not sure this class makes sense yet. It might be smarter to have a
# FakeJournal.new(...).basic(...), returning a Journal, instead of what we're 
# doing now. (Or, faker.new.basic_journal(...))
class FakeJournal
  def basic_cash(from, to, adds_up_to, num_postings)
    raise StandardError unless [from.kind_of?(Date), to.kind_of?(Date), 
      adds_up_to.kind_of?(RRA::Journal::Commodity), 
      num_postings.kind_of?(Numeric)].all?

    day_increment = (((to-from).to_f.abs+1)/(num_postings-1)).floor

    # If we have more postings than days, I guess, raise Unsupported
    raise StandardError if day_increment <= 0

    amount_increment = (adds_up_to / num_postings).floor adds_up_to.precision
    running_sum = nil

    RRA::Journal.new 1.upto(num_postings).to_a.collect{ |n|
      post_amount = (n == num_postings) ? (adds_up_to - running_sum) : amount_increment
      post_date = (n == num_postings) ? to : from+(day_increment*(n-1))

      running_sum = (running_sum.nil?) ? post_amount : (running_sum + post_amount)

			simple_posting post_date, post_amount 
    }
  end

	private

	def simple_posting(date, amount)
    RRA::Journal::Posting.new date, 'Simple Payee', transfers: [ 
      to_transfer('Expense', commodity: amount), to_transfer('Cash') ]
	end

  def to_transfer(*args)
    RRA::Journal::Posting::Transfer.new(*args)
  end

end
