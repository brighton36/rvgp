require_relative '../journal'

module RRA::Transformers
  class JournalTransformer < RRA::TransformerBase
    attr_reader :accounts

    private

    def journal
      RRA::Journal.parse File.read(input_file)
    end

    def source_postings
      @source_postings ||= journal.postings.collect{|posting|
        raise StandardError, 'Unimplemented posting on: %s:%d' % [input_file,
          posting.line_number] unless ( 
          posting.transfers.first.commodity and
          posting.transfers.last.commodity.nil?)

        # For Journal:Posting's with multiple account transfer lines, we break it into 
        # multiple RRA::TransformerBase::Posting postings.
        posting.transfers[...-1].collect do |transfer|
          # NOTE: The tags.dup appears to be needed, because otherwise the 
          #       tags array ends up shared between the two entries, and 
          #       operations on one, appear in the other's contents
          RRA::TransformerBase::Posting.new posting.line_number, date: posting.date, 
            tags: posting.tags.dup, from: from, description: posting.description,
            commodity: transform_commodity(transfer.commodity),
            to: transfer.account
        end
      }.flatten
    end
  end
end
