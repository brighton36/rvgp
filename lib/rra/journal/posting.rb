# frozen_string_literal: true

module RRA
  class Journal
    # This class represents a single posting, in a PTA journal. A posting is
    # typically of the following form:
    # ```
    #     2020-02-10 Frozen Chicken from the Local Supermarket
    #       Personal:Expenses:Food:Groceries    $ 50.00
    #       Cash
    # ```
    # Though, this is a simple example. And, there are a good number of permutations
    # in which postings appear. Nonetheless, a posting is typically comprised of
    # a date, a description, and a number of RRA::Journal::Posting::Transfer lines,
    # indented below these fields. This object represents the parsed format,
    # of a post, traveling around the RRA codebase.
    class Posting
      # This class represents an indented 'transfer' line, within a posting.
      # Typically, such lines takes the form of :
      # ```
      #   Personal:Expenses:Food:Groceries    $ 50.00
      # ```
      # This class offers few functions, and mostly just offers its attributes
      class Transfer
        attr :account, :commodity, :complex_commodity, :tags

        def initialize(account, opts = {})
          @account = account
          @commodity = opts[:commodity]
          @complex_commodity = opts[:complex_commodity]
          @tags = opts[:tags] || []
        end
      end

      # This class represents a key, or key/value tag, within a journal.
      # These tags can be affixed to transfers and postings. And, are pretty
      # simple, comprising of a key and optionally, a value.
      class Tag
        attr :key, :value

        def initialize(key, value = nil)
          @key = key
          @value = value
        end

        def to_s
          value ? [key, value].join(': ') : key
        end

        def self.from_s(str)
          /\A(.+) *: *(.+)\Z/.match(str) ? Tag.new(::Regexp.last_match(1), ::Regexp.last_match(2)) : Tag.new(str)
        end
      end

      attr :line_number, :date, :description, :transfers, :tags

      def initialize(date, description, opts = {})
        @line_number = opts[:line_number]
        @date = date
        @description = description
        @transfers = opts.key?(:transfers) ? opts[:transfers] : []
        @tags = opts.key?(:tags) ? opts[:tags] : []
      end

      def valid?
        # Required fields:
        [date, description, transfers, transfers.any? { |t| t.account && (t.commodity || t.complex_commodity) }].all?
      end

      def to_ledger
        max_to_length = transfers.map do |transfer|
          transfer.commodity || transfer.complex_commodity ? transfer.account.length : 0
        end.max

        lines = [[date, description].join(' ')]
        lines.insert(lines.length > 1 ? -2 : 1, format('  ; %s', tags.join(', '))) if tags && !tags.empty?
        lines += transfers.map do |transfer|
          [
            if transfer.commodity || transfer.complex_commodity
              format("  %<account>-#{max_to_length}s    %<commodity>s",
                     account: transfer.account,
                     commodity: (transfer.commodity || transfer.complex_commodity).to_s)
            else
              format('  %s', transfer.account)
            end,
            transfer.tags && !transfer.tags.empty? ? transfer.tags.map { |tag| format('  ; %s', tag) } : nil
          ].compact.flatten.join("\n")
        end
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
        (transfers.empty? ? tags : transfers.last.tags) << tag
      end
    end
  end
end
