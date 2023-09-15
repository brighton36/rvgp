# frozen_string_literal: true

require 'bigdecimal'

module RRA
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
  # class expects a string. The conversion process is fairly smart, in that a specified rate, works 'both ways'.
  # Meaning that, a price query will resolve based on any stipulation of equivalence between commodities. And,
  # the matter of which code is to the left, or right, of a ratio, is undifferentiated from the inverse arrangement.
  # This behavior, and most all others in this class, mimics the way ledger works wrt price conversion.
  class Pricer
    # This class represents a parsed line, representing a exchange rate.
    # This class contains a datetime, an amount, and two codes.
    class Price < RRA::PtaAdapter::ReaderBase
      readers :at, :lcode, :rcode, :amount

      def to_key
        self.class.to_key lcode, rcode
      end

      def self.to_key(code1, code2)
        [code1, code2].sort.join(' ')
      end
    end

    class NoPriceError < StandardError; end

    MSG_UNEXPECTED_LINE = 'Unexpected at line %d: %s'
    MSG_INVALID_PRICE = 'Missing one or more required elements at line %d: %s'
    MSG_INVALID_DATETIME = 'Invalid datetime at line %d: %s'

    attr_reader :prices_db

    def initialize(prices_content = nil, opts = {})
      @prices_db = prices_content ? parse(prices_content) : {}
      @before_price_add = opts[:before_price_add] if opts[:before_price_add]
    end

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
        RRA::Journal::Commodity.from_symbol_and_amount to, (1 / price.amount.quantity_as_bigdecimal).round(17).to_s('F')
      end
    end

    def convert(at, from_commodity, to_code_or_symbol)
      rate = price at, from_commodity.code, to_code_or_symbol

      RRA::Journal::Commodity.from_symbol_and_amount(
        to_code_or_symbol,
        (from_commodity.quantity_as_bigdecimal * rate.quantity_as_bigdecimal).to_s('F')
      )
    end

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
