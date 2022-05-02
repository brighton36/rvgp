
class RRA::Journal
  MSG_MISSING_POSTING_SEPARATOR = "Missing a blank line before line %d: %s"
  MSG_UNRECOGNIZED_HEADER = "Unrecognized posting header at line %d: %s"
  MSG_INVALID_DATE = "Invalid posting date at line %d: %s"
  MSG_UNEXPECTED_TRANSFER = "Unexpected transfer at line %d: %s"
  MSG_UNEXPECTED_TAG = "Unexpected tag at line %d: %s"
  MSG_UNEXPECTED_LINE = "Unexpected at line %d: %s"
  MSG_INVALID_TRANSFER_COMMODITY = "Unparseable or unimplemented commodity-parse in transfer at line %d: %s"
  MSG_INVALID_POSTING = "Invalid Posting at separator line %d: %s"
  MSG_TOO_MANY_SEMICOLONS = "Too many semicolons at line %d. Are these comments? %s"
  MSG_UNPARSEABLE_TRANSFER = "Something is wrong with this transfer at line %d: %s"
  
  attr :postings
  
  def initialize(postings)
    @postings = postings
  end

  def to_s
    @postings.collect{|posting| posting.to_ledger}.join "\n\n"
  end

  def self.parse(contents)
    postings = []

    posting = nil
    cite = nil
    contents.lines.each_with_index do |line, i|
      line_number = i+1
      cite = [line_number, line.inspect] # in case we run into an error
      line_comment = nil

      # Here, we separate the line into non-comment lvalue and comment rvalue:
      # NOTE: We're not supporting escaped semicolons, at this time
      if /\A.*[^\\]\;.*[^\\]\;.*\Z/.match line
        raise StandardError, MSG_TOO_MANY_SEMICOLONS % cite
      elsif /\A([ ]*.*?)[ ]*\;[ \t]*(.*)\Z/.match line
        line, line_comment = $1, $2
      end

      # This case parses anything to the left of a comment:
      case line
        when /\A([^ \n].*)\Z/
          # This is a post declaration line
          raise StandardError, MSG_MISSING_POSTING_SEPARATOR % cite if posting
          raise StandardError, MSG_UNRECOGNIZED_HEADER % cite unless \
            /\A([\d]{4})[\/\-]([\d]{2})[\/\-]([\d]{2})[ ]+(.+?)[ ]*\Z/.match $1

          begin
            date = Date.new $1.to_i, $2.to_i, $3.to_i
          rescue Date::Error
            raise StandardError, MSG_INVALID_DATE % cite
          end

          posting = Posting.new date, $4, line_number: line_number
        when /\A[ \t]+([^ ].+)\Z/
          # This is a transfer line, to be appended to the current posting
          raise StandardError, MSG_UNEXPECTED_TRANSFER % cite unless posting

          # NOTE: We chose 2 or more spaces as the separator between
          # the account and the commodity, mostly because this was the smallest
          # we could find in the official ledger documentation
          raise StandardError, MSG_UNPARSEABLE_TRANSFER % cite unless \
            /\A(.+?)(?:[ ]{2,}([^ ].+)|[ ]*)\Z/.match $1
          
          begin
            posting.append_transfer $1, $2
          rescue RRA::Journal::Commodity::Error
            raise StandardError, MSG_INVALID_TRANSFER_COMMODITY % cite
          end
        when /\A[ \t]*\Z/
          if line_comment.nil? and posting
            unless posting.valid?
              posting.transfers.each do |transfer|
                puts "  - Not valid. account %s commodity: %s complex_commodity: %s" % [
                  transfer.account.inspect, transfer.commodity.inspect, 
                  transfer.complex_commodity.inspect ]
              end
            end

            raise StandardError, MSG_INVALID_POSTING % cite unless posting.valid?

            # This is a blank line
            postings << posting
            posting = nil
          end
        else
          raise StandardError, MSG_UNEXPECTED_LINE % cite unless posting
      end

      line_comment.scan(/(?:[^ ]+\:[ ]*[^\,]*|\:[^ \t]+\:)/).collect{|declaration| 
        /\A[\:]?(.+)\:\Z/.match(declaration) ? $1.split(':') : declaration
      }.flatten.each{ |tag| posting.append_tag tag } if line_comment and posting
    end

    # The last line could be \n, which, makes this unnecessary
    if posting
      raise StandardError, MSG_INVALID_POSTING % cite unless posting.valid?
      postings << posting
    end

    self.new postings
  end
end
