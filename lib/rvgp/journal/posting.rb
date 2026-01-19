# frozen_string_literal: true

module RVGP
  module Journal
    # This class represents a single posting, in a PTA journal. A posting is
    # typically of the following form:
    # ```
    # 2020-02-10 Frozen Chicken from the Local Supermarket
    #   Personal:Expenses:Food:Groceries    $ 50.00
    #   Cash
    # ```
    # This is a simple example. There are a good number of permutations under which
    # posting components s appear. Nonetheless, a posting is typically comprised of
    # a date, a description, and a number of RVGP::Journal::Posting::Transfer lines,
    # indented below these fields. This object represents the parsed format,
    # of a post, traveling around the RVGP codebase.
    # @attr_reader [Integer] line_number The line number, in a journal, that this posting was declared at.
    # @attr_reader [Date] date The date this posting occurred
    # @attr_reader [String] description The first line of this posting
    # @attr_reader [Array<RVGP::Journal::Posting::Transfer>] transfers An array of transfers, that apply to this
    #                                                                  posting.
    # @attr_reader [Array<RVGP::Journal::Posting::Tag>] tags An array of tags, that apply to this posting.
    class Posting
      # This class represents an indented 'transfer' line, within a posting.
      # Typically, such lines takes the form of :
      # ```
      #   Personal:Expenses:Food:Groceries    $ 50.00
      # ```
      # This class offers few functions, and mostly just offers its attributes. Note
      # that there should be no reason a posting ever has both is commodity and complex_commodity
      # set. Either one or the other should exist, for any given Transfer.
      # @attr_reader [String] account The account this posting is crediting or debiting
      # @attr_reader [String] effective_date The effective date of this transfer {See https://ledger-cli.org/doc/ledger3.html#Effective-Dates}
      # @attr_reader [String] commodity The amount (expressed in commodity terms) being credit/debited
      # @attr_reader [String] complex_commodity The amount (expressed in complex commodity terms) being credit/debited
      # @attr_reader [Array<RVGP::Journal::Posting::Tag>] tags An array of tags, that apply to this posting.
      class Transfer
        attr :account, :effective_date, :commodity, :complex_commodity, :tags

        # Create a complex commodity, from constituent parts
        # @param [String] account see {Transfer#account}
        # @param [Hash] opts Additional parts of this Transfer
        # @option opts [String] effective_date see {Transfer#effective_date}
        # @option opts [String] commodity see {Transfer#commodity}
        # @option opts [String] complex_commodity see {Transfer#complex_commodity}
        # @option opts [Array<RVGP::Journal::Posting::Tag>] tags ([]) see {Transfer#tags}
        def initialize(account, opts = {})
          @account = account
          @effective_date = opts[:effective_date]
          @commodity = opts[:commodity]
          @complex_commodity = opts[:complex_commodity]
          @tags = opts[:tags] || []
        end
      end

      # This class represents a key, or key/value tag, within a journal.
      # These tags can be affixed to transfers and postings. And, are pretty
      # simple, comprising of a key and optionally, a value.
      # @attr_reader [String] key The label of this tag
      # @attr_reader [String] value The value of this tag
      class Tag
        attr :key, :value

        # Create a tag from it's constituent parts
        # @param [String] key see {Tag#key}
        # @param [String] value (nil) see {Tag#value}
        def initialize(key, value = nil)
          @key = key
          @value = value
        end

        # Serialize this tag, to a string
        # @return [String] the tag, as would be found in a pta journal
        def to_s
          value ? [key, value].join(': ') : key
        end

        # Parse the provided string, into a Tag object
        # @param [String] str The tag, possibly a key/value pair, as would be found in a pta journal
        # @return [Tag] A parsed representation of this tag
        def self.from_s(str)
          /\A(.+) *: *(.+)\Z/.match(str) ? Tag.new(::Regexp.last_match(1), ::Regexp.last_match(2)) : Tag.new(str)
        end
      end

      attr :line_number, :date, :description, :transfers, :tags

      # Create a posting, from constituent parts
      # @param [Date] date see {Posting#date}
      # @param [String] description see {Posting#description}
      # @param [Hash] opts Additional parts of this Posting
      # @option opts [Array<RVGP::Journal::Posting::Transfer>] transfers see {Posting#transfers}
      # @option opts [Array<RVGP::Journal::Posting::Tag>] tags see {Posting#transfers}
      def initialize(date, description, opts = {})
        @line_number = opts[:line_number]
        @date = date
        @description = description
        @transfers = opts.key?(:transfers) ? opts[:transfers] : []
        @tags = opts.key?(:tags) ? opts[:tags] : []
      end

      # Indicates whether or not this instance contains all required fields
      # @return [TrueClass,FalseClass] whether or not we're valid
      def valid?
        # Required fields:
        [date, description, transfers, transfers.any? { |t| t.account && (t.commodity || t.complex_commodity) }].all?
      end

      # Serializes this posting into a string, in the form that would be found in a PTA journal
      # @return [String] The PTA journal representation of this posting
      def to_ledger
        max_to_length = transfers.map do |transfer|
          transfer.commodity || transfer.complex_commodity ? transfer.account.length : 0
        end.max

        lines = [[date, description].join(' ')]
        lines.insert(lines.length > 1 ? -2 : 1, format('  ; %s', tags.join(', '))) if tags && !tags.empty?
        lines += transfers.map do |transfer|
          [
            if transfer.commodity || transfer.complex_commodity
              format("  %<account>-#{max_to_length}s    %<commodity>s%<effective_date>s",
                     account: transfer.account,
                     commodity: (transfer.commodity || transfer.complex_commodity).to_s,
                     effective_date: transfer.effective_date ? format('  ; [=%s]', transfer.effective_date.to_s) : nil)
            else
              format('  %s', transfer.account)
            end,
            transfer.tags && !transfer.tags.empty? ? transfer.tags.map { |tag| format('  ; %s', tag) } : nil
          ].compact.flatten.join("\n")
        end
        lines.join("\n")
      end

      # The append_*() is really only intended to be called by the parser:
      # @!visibility private
      def append_transfer(account_part, commodity_part)
        opts = {}
        if commodity_part
          # Let's see if it'll parse as a commodity:
          begin
            opts[:commodity] = RVGP::Journal::Commodity.from_s commodity_part
          rescue RVGP::Journal::Commodity::UnimplementedError
            # Then let's see if it parses as a commodity pair
            opts[:complex_commodity] = RVGP::Journal::ComplexCommodity.from_s commodity_part
          end
        end

        @transfers << Transfer.new(account_part, opts)
      end

      # This is really only intended to simpify the parser, we push this onto the
      # bottom of whatever exists here
      # @!visibility private
      def append_tag(as_string)
        tag = Tag.from_s as_string
        (transfers.empty? ? tags : transfers.last.tags) << tag
      end
    end
  end
end
