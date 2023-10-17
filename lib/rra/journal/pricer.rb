# frozen_string_literal: true

require 'bigdecimal'

module RRA
  class Journal
    # This class takes a value, denominated in one commodity, and returns the equivalent value, in another commodity.
    # This process is also known as price (or currency) exchange. The basis for exchanges are rates, affixed to a
    # date. These exchange rates are expected to be provided in the same format that ledger and hledger use. Here's an
    # example:
    # ```
    #   P 2020-01-01 USD 0.893179 EUR
    #   P 2020-02-01 EUR 1.109275 USD
    #   P 2020-03-01 USD 0.907082 EUR
    # ```
    # It's typical for these exchange rates to exist in a project's journals/prices.db, but, the constructor to this
    # class expects the contents of such a file, as a string. The conversion process is fairly smart, in that a
    # specified rate, works 'both ways'. Meaning that, a price query will resolve based on any stipulation of
    # equivalence between commodities. And, the matter of which code is to the left, or right, of a ratio, is
    # undifferentiated from the inverse arrangement. This behavior, and most all others in this class, mimics the way
    # ledger works, wrt price conversion.
    # @attr_reader [Array<Pricer::Price>] prices_db A parsed representation of the prices file, based on what was passed
    #                                               in the constructor.
    class Pricer
      # This class represents a line, parsed from a prices journal. And, an instance of this class
      # represents an exchange rate.
      # This class contains a datetime, an amount, and two codes.
      # @attr_reader [Time] at The time at which this exchange rate was declared in effect
      # @attr_reader [String] lcode The character alphabetic code, or symbol for the left side of the exchange pair
      # @attr_reader [String] rcode The character alphabetic code, or symbol for the right side of the exchange pair.
      #                             This code should (always?) match the amount.code
      # @attr_reader [RRA::Journal::Commodity] amount The ratio of lcode, to rcode. Aka: The exchange rate.
      class Price < RRA::Base::Reader
        readers :at, :lcode, :rcode, :amount

        # A shortcut, to {RRA::Journal::Pricer::Price.to_key}, if a caller is looking to use this price in a Hash
        # @return [String] A code, intended for use in Hash table lookups
        def to_key
          self.class.to_key lcode, rcode
        end

        # Create a string, for this pair, that is unique to the codes, regardless of the order in which they're
        # provided. This enables us to assert bidirectionality in the lookup of prices.
        # @param [String] code1 A three character alphabetic currency code
        # @param [String] code2 A three character alphabetic currency code
        # @return [String] A code, intended for use in Hash table lookups
        def self.to_key(code1, code2)
          [code1, code2].sort.join(' ')
        end
      end

      # This Error is raised when we're unable to perform a price conversion
      class NoPriceError < StandardError; end

      # @!visibility private
      MSG_UNEXPECTED_LINE = 'Unexpected at line %d: %s'
      # @!visibility private
      MSG_INVALID_PRICE = 'Missing one or more required elements at line %d: %s'
      # @!visibility private
      MSG_INVALID_DATETIME = 'Invalid datetime at line %d: %s'

      attr_reader :prices_db

      # Create a Price exchanger, given a prices database
      # @param [String] prices_content The contents of a prices.db file, defining the exchange rates.
      # @param [Hash] opts Optional features
      # @option opts [Proc<Time,String,String>] before_price_add
      #   This option calls the provided Proc with the parameters offered to {#add}.
      #   Mostly, this exists to solve a very specific bug that occurs under certain
      #   conditions, in projects where currencies are automatically converted by
      #   ledger. If you see the I18n.t(error.missing_entry_in_prices_db) message
      #   in your build log, scrolling by - you should almost certainly add that entry
      #   to your project's prices.db. And this option is how that notice was fired.
      #
      #   This option 'addresses' a pernicious bug that will likely affect you. And
      #   I don't have an easy solution, as, I sort of blame ledger for this.
      #   The problem will manifest itself in the form of grids that output
      #   differently, depending on what grids were built in the process.
      #
      #   So, If, say, we're only building 2022 grids. But, a clean build
      #   would have built 2021 grids, before instigating the 2022 grid
      #   build - then, we would see different outputs in the 2022-only build.
      #
      #   The reason for this, is that there doesn't appear to be any way of
      #   accounting for all historical currency conversions in ledger's output.
      #   The data coming out of ledger only includes currency conversions in
      #   the output date range. This will sometimes cause weird discrepencies
      #   in the totals between a 2021-2022 run, vs a 2022-only run.
      #
      #   The only solution I could think of, at this time, was to burp on
      #   any occurence, where, a conversion, wasn't already in the prices.db
      #   That way, an operator (you) can simply add the outputted burp, into
      #   the prices.db file. This will ensure consistency in all grids,
      #   regardless of the ranges you run them.
      #
      #   NOTE: This feature is currently unimplemnted in hledger. And, I have no
      #   solution planned there at this time. Probably, that means you should
      #   only use ledger in your project, if you're working with multiple currencies,
      #   and don't want to rebuild your project from clean, every time you make
      #   non-trivial changes.
      #
      #   If you have a better idea, or some other way to ensure consistency
      #   (A SystemValidation?)... PR's welcome!
      def initialize(prices_content = nil, opts = {})
        @prices_db = prices_content ? parse(prices_content) : {}
        @before_price_add = opts[:before_price_add] if opts[:before_price_add]
      end

      # Retrieve an exchange rate, for a given commodity, to another commodity, at a given time.
      # @param [Time] at The time at which you want to query for an exchange rate. The most-recently-availble and
      #                  eligible entry, before this parameter, will be selected.
      # @param [String] from The three character alphabetic currency code, of the source currency
      # @param [String] to The three character alphabetic currency code, of the destination currency
      # @return [RRA::Journal::Commodity] An exchange rate, denominated in units of the :to currency
      def price(at, from, to)
        no_price! at, from, to if prices_db.nil? || prices_db.empty?

        lcurrency = RRA::Journal::Currency.from_code_or_symbol from
        from_alpha = lcurrency ? lcurrency.alphabetic_code : from

        rcurrency = RRA::Journal::Currency.from_code_or_symbol to
        to_alpha = rcurrency ? rcurrency.alphabetic_code : to

        prices = prices_db[Price.to_key(from_alpha, to_alpha)]

        no_price! at, from, to unless prices && !prices.empty? && at >= prices.first.at

        price = nil

        1.upto(prices.length - 1) do |i|
          if prices[i].at > at
            price = prices[i - 1]
            break
          end
        end

        price = prices.last if price.nil? && prices.last.at <= at

        no_price! at, from, to unless price

        # OK, so we have the price record that applies. But, it may need to be
        # inverted.
        if price.lcode == from_alpha && price.amount.alphabetic_code == to_alpha
          price.amount
        else
          RRA::Journal::Commodity.from_symbol_and_amount to,
                                                         (1 / price.amount.quantity_as_bigdecimal).round(17).to_s('F')
        end
      end

      # Convert the provided commodity, to another commodity, based on the rate at a given time.
      # @param [Time] at The time at which you want to query for an exchange rate. The most-recently-availble and
      #                  eligible entry, before this parameter, will be selected.
      # @param [RRA::Journal::Commodity] from_commodity The commodity you wish to convert
      # @param [String] to_code_or_symbol The three character alphabetic currency code, or symbol, of the destination
      #                                   currency you wish to convert to.
      # @return [RRA::Journal::Commodity] The resulting commodity, in units of :to_code_or_symbol
      def convert(at, from_commodity, to_code_or_symbol)
        rate = price at, from_commodity.code, to_code_or_symbol

        RRA::Journal::Commodity.from_symbol_and_amount(
          to_code_or_symbol,
          (from_commodity.quantity_as_bigdecimal * rate.quantity_as_bigdecimal).to_s('F')
        )
      end

      # Add a conversion rate to the database
      # @param [Time] time The time at which this rate was discovered
      # @param [String] from_alpha The three character alphabetic currency code, of the source currency
      # @param [RRA::Journal::Currency] to A commodity, expressing the quantity and commodity, that one
      #                                    unit of :from_alpha converts to
      # @return [void]
      def add(time, from_alpha, to)
        lcurrency = RRA::Journal::Currency.from_code_or_symbol from_alpha

        price = Price.new time.to_time,
                          lcurrency ? lcurrency.alphabetic_code : from_alpha,
                          to.alphabetic_code || to.code,
                          to

        key = price.to_key
        if @prices_db.key? key
          i = @prices_db[key].find_index { |p| p.at > price.at.to_time }

          # There's no need to add the price, if there's no difference between
          # what we're adding, and what would have been found, otherwise
          price_before_add = i ? @prices_db[key][i - 1] : @prices_db[key].last

          if price_before_add.amount != price.amount
            @before_price_add&.call time, from_alpha, to

            if i
              @prices_db[key].insert i, price
            else
              @prices_db[key] << price
            end
          end

        else
          @before_price_add&.call time, from_alpha, to
          @prices_db[key] = [price]
        end

        price
      end

      private

      def parse(contents)
        posting = nil
        parsed_lines = contents.lines.map.with_index do |line, i|
          cite = [i + 1, line.inspect] # in case we run into an error

          # Remove any comments from the line:
          line = ::Regexp.last_match(1) if /(.*) *;.*/.match line

          case line
          when %r{\AP[ ]+
            # Date:
            (\d{4}[\-/]\d{1,2}[\-/]\d{1,2})
            # Time:
            (?:[ ]+(\d{1,2}:\d{1,2}:\d{1,2})|)
            # Symbol:
            [ ]+([^ ]+)
            # Commodity:
            [ ]+(.+?)
            [ ]*\Z}x

            # NOTE: This defaults to the local time zone. Not sure if we care.
            begin
              time = Time.new(
                *[::Regexp.last_match(1).tr('/', '-').split('-').map(&:to_i),
                  ::Regexp.last_match(2) ? ::Regexp.last_match(2).split(':').map(&:to_i) : nil].flatten.compact
              )
            rescue ArgumentError
              raise StandardError, MSG_INVALID_DATETIME % cite
            end

            lcurrency = RRA::Journal::Currency.from_code_or_symbol ::Regexp.last_match(3)
            amount = ::Regexp.last_match(4).to_commodity

            Price.new time,
                      lcurrency ? lcurrency.alphabetic_code : ::Regexp.last_match(3),
                      amount.alphabetic_code || amount.code, amount

          when /\A *\Z/
            # Blank Line
            nil
          else
            raise StandardError, MSG_UNEXPECTED_LINE % cite unless posting
          end
        end.compact.sort_by(&:at)

        parsed_lines.each_with_object({}) do |price, sum|
          key = price.to_key
          sum[key] = [] unless sum.key? key
          sum[key] << price
          sum
        end
      end

      def no_price!(at, from, to)
        raise NoPriceError, format('Unable to convert %<from>s to %<to>s at %<at>s', from: from, to: to, at: at.to_s)
      end
    end
  end
end
