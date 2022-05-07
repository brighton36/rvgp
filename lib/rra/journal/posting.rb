
class RRA::Journal::Posting
  class Transfer
    attr :account, :commodity, :complex_commodity, :tags
    
    def initialize(account, opts = {})
      @account, @commodity, @complex_commodity, @tags = account, opts[:commodity], 
        opts[:complex_commodity], (opts[:tags] || [])
    end
  end

  class Tag
    attr :key, :value

    def initialize(key, value = nil)
      @key, @value = key, value
    end

    def to_s
      (value) ? [key, value].join(': ') : key
    end

    def self.from_s(s)
      /\A(.+)[ ]*\:[ ]*(.+)\Z/.match(s) ? Tag.new($1, $2) : Tag.new(s)
    end
  end

  attr :line_number, :date, :description, :transfers, :tags

  def initialize(date, description, opts = {})
    @line_number = opts[:line_number]
    @date, @description = date, description
    @transfers = opts.has_key?(:transfers) ? opts[:transfers] : []
    @tags = opts.has_key?(:tags) ? opts[:tags] : []
  end
  
  def valid?
    # Required fields:
    [date, description, transfers, 
     transfers.any?{|t| t.account && (t.commodity || t.complex_commodity)}].all?
  end

  def to_ledger
    max_to_length = transfers.collect{|transfer| 
      (transfer.commodity || transfer.complex_commodity) ? transfer.account.length : 0}.max

    lines = ["%s %s" % [date, description]]
    lines.insert((lines.length > 1) ? -2 : 1, '  ; %s' % tags.join(', ')) if (
      tags && tags.length > 0)
    lines += transfers.collect{|transfer| 
      [(transfer.commodity || transfer.complex_commodity) ? 
        "  %-#{max_to_length}s    %s" % [
          transfer.account, 
          (transfer.commodity || transfer.complex_commodity).to_s
        ] :
        "  %s" % [transfer.account], 
        (transfer.tags && transfer.tags.length > 0) ? 
          transfer.tags.collect{|tag| '  ; %s' %  tag } : nil
      ].compact.flatten.join("\n") } 
    lines.join("\n")
  end

  # The append_*() is really only intended to be called by the parser:
  def append_transfer(account_part, commodity_part)
    opts = {}
    if commodity_part
      # Let's see if it'll parse as a commodity:
      begin
        opts[:commodity] = RRA::Journal::Commodity.from_s commodity_part
      rescue RRA::Journal::Commodity::UnimplementedError
        # Then let's see if it parses as a commodity pair
        opts[:complex_commodity] = RRA::Journal::ComplexCommodity.from_s commodity_part
      end
    end

    @transfers << Transfer.new(account_part, opts)
  end

  # This is really only intended to simpify the parser, we push this onto the
  # bottom of whatever exists here
  def append_tag(as_string)
    tag = Tag.from_s as_string
    ((transfers.length > 0) ? transfers.last.tags : tags) << tag
  end

end
