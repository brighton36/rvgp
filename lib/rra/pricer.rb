require 'bigdecimal'

module RRA
  class Pricer
    class Price < RRA::PTAConnection::ReaderBase
      readers :at, :lcode, :rcode, :amount

      def to_key
        self.class.to_key lcode, rcode
      end

      def self.to_key(code1, code2)
        [code1, code2].sort.join(' ')
      end
    end

    class NoPriceError < StandardError; end

    MSG_UNEXPECTED_LINE = "Unexpected at line %d: %s"
    MSG_INVALID_PRICE = "Missing one or more required elements at line %d: %s"
    MSG_INVALID_DATETIME = "Invalid datetime at line %d: %s"

    attr_reader :prices_db

    def initialize(prices_content = nil, opts = {})
      @prices_db = (prices_content) ? parse(prices_content) : Hash.new
      @before_price_add = opts[:before_price_add] if opts[:before_price_add]
    end

    def price(at, from, to)
      no_price! at, from, to if prices_db.nil? or prices_db.length == 0

      lcurrency = RRA::Journal::Currency.from_code_or_symbol from
      from_alpha = (lcurrency) ? lcurrency.alphabetic_code : from

      rcurrency = RRA::Journal::Currency.from_code_or_symbol to
      to_alpha = (rcurrency) ? rcurrency.alphabetic_code : to

      key = Price.to_key(from_alpha, to_alpha)

      prices = prices_db[Price.to_key(from_alpha, to_alpha)]

      no_price! at, from, to unless (prices and prices.length > 0 and 
        at >= prices.first.at)

      price = nil

      1.upto(prices.length-1) do |i|
        if prices[i].at > at
          price = prices[i-1] 
          break
        end
      end

      price = prices.last if price.nil? and prices.last.at <= at

      no_price! at, from, to unless price

      # OK, so we have the price record that applies. But, it may need to be
      # inverted.
      (price.lcode == from_alpha and price.amount.alphabetic_code == to_alpha) ?
        price.amount : RRA::Journal::Commodity.from_symbol_and_amount( 
          to, (1 / price.amount.quantity_as_bigdecimal).round(17).to_s('F'))
    end

    def convert(at, from_commodity, to_code_or_symbol)
      rate = price at, from_commodity.code, to_code_or_symbol

      RRA::Journal::Commodity.from_symbol_and_amount(to_code_or_symbol,(
        from_commodity.quantity_as_bigdecimal*rate.quantity_as_bigdecimal
        ).to_s('F'))
    end

    def add(time, from_alpha, to)
      lcurrency = RRA::Journal::Currency.from_code_or_symbol from_alpha

      price  = Price.new time.to_time, 
        (lcurrency) ? lcurrency.alphabetic_code : from_alpha, 
        to.alphabetic_code || to.code, to

      key = price.to_key
      if @prices_db.has_key? key
        i = @prices_db[key].find_index{|p| p.at > price.at.to_time }

        # There's no need to add the price, if there's no difference between
        # what we're adding, and what would have been found, otherwise
        price_before_add = i ? @prices_db[key][i-1] : @prices_db[key].last

        if price_before_add.amount != price.amount
          @before_price_add.call time, from_alpha, to if @before_price_add

          if i
            @prices_db[key].insert i, price
          else
            @prices_db[key] << price
          end
        end

      else
        @before_price_add.call time, from_alpha, to if @before_price_add
        @prices_db[key] = [price]
      end

      price
    end

    private

    def parse(contents)
      posting = nil
      prices = contents.lines.collect.with_index{ |line, i|
        cite = [i+1, line.inspect] # in case we run into an error

        # Remove any comments from the line:
        line = $1 if /(.*)[ ]*[\;].*/.match line

        case line
          when /\AP[ ]+
            # Date:
            ([\d]{4}[\-\/][\d]{1,2}[\-\/][\d]{1,2})
            # Time:
            (?:[ ]+([\d]{1,2}\:[\d]{1,2}\:[\d]{1,2})|)
            # Symbol:
            [ ]+([^ ]+)
            # Commodity:
            [ ]+(.+?)
            [ ]*\Z/x

            # NOTE: This defaults to the local time zone. Not sure if we care.
            begin
              time = Time.new *[$1.tr('/', '-').split('-').collect(&:to_i),
                ($2) ? $2.split(':').collect(&:to_i) : nil ].flatten.compact
            rescue ArgumentError
              raise StandardError, MSG_INVALID_DATETIME % cite
            end

            lcurrency = RRA::Journal::Currency.from_code_or_symbol $3
            amount = $4.to_commodity

            Price.new time, (lcurrency) ? lcurrency.alphabetic_code : $3, 
              amount.alphabetic_code || amount.code, amount
              
          when /\A[ ]*\Z/
            # Blank Line
            nil
          else
            raise StandardError, MSG_UNEXPECTED_LINE % cite unless posting
        end
      }.compact.sort_by(&:at).inject(Hash.new){|sum, price|
        key = price.to_key
        sum[key] = Array.new unless sum.has_key? key
        sum[key] << price
        sum
      }
    end

    def no_price!(at, from, to)
      raise NoPriceError, "Unable to convert %s to %s at %s" % [from, to, at.to_s]
    end

  end
end
