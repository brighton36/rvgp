require 'rra/journal'
require 'rra/journal/commodity'

# NOTE: I'm not sure this class makes sense yet. It might be smarter to have a
# FakeJournal.new(...).basic(...), returning a Journal, instead of what we're 
# doing now. (Or, faker.new.basic_journal(...))
class FakeJournal
  def basic_cash(from, to, adds_up_to, num_postings)
    # Type Check
    raise StandardError unless [from.kind_of?(Date), to.kind_of?(Date), 
      adds_up_to.kind_of?(RRA::Journal::Commodity), 
      num_postings.kind_of?(Numeric)].all?

    days_in_range = ((to-from).to_f.abs/num_postings+1).floor
    increment = adds_up_to / num_postings
    
    RRA::Journal.new 1.upto(num_postings).to_a.collect{ |n|
			simple_posting from+(days_in_range*(n-1)), increment }
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
