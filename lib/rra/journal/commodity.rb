# frozen_string_literal: true

require 'bigdecimal'

module RRA
  class Journal
    # This abstraction defines a simple commodity, as would be found in a pta journal.
    # Such commodities can appear in the form of currency, such as '$ 1.30' or
    # in any other format that hledger and ledger parse. ie '1 HOUSE'.
    #
    # Many helper functions are offered here, including math functions.
    #
    # NOTE: the easiest way to create a commodity in your code, is by way of the
    # provided String#to_commodity method. Such as: '$ 1.30'.to_commodity
    #
    # Units of a commodity are stored in int's, with precision. This ensures that
    # there is no potential for floating point precision errors, affecting these
    # commodities.
    class Commodity
      attr_accessor :quantity, :code, :alphabetic_code, :precision

      MATCH_AMOUNT = '([-]?[ ]*?[\d\,]+(?:\\.[\d]+|))'
      MATCH_CODE = '(?:(?<!\\\\)\"(.+)(?<!\\\\)\"|([^ \-\d]+))'
      MATCH_COMMODITY = ['\\A(?:', MATCH_CODE, '[ ]*?', MATCH_AMOUNT, '|', MATCH_AMOUNT, '[ ]*?', MATCH_CODE].freeze

      MATCH_COMMODITY_WITHOUT_REMAINDER = Regexp.new((MATCH_COMMODITY + [')\\Z']).join)
      MATCH_COMMODITY_WITH_REMAINDER = Regexp.new((MATCH_COMMODITY + [')(.*?)\\Z']).join)

      # This appears to be a ruby limit, in float's
      MAX_DECIMAL_DIGITS = 17

      class ConversionError < StandardError; end
      class UnimplementedError < StandardError; end

      def initialize(code, alphabetic_code, quantity, precision)
        @code = code
        @alphabetic_code = alphabetic_code
        @quantity = quantity.to_i
        @precision = precision.to_i
      end

      def quantity_as_s(options = {})
        characteristic, mantissa = if options.key? :precision
                                     round(options[:precision]).quantity_as_decimal_pair
                                   else
                                     quantity_as_decimal_pair
                                   end

        characteristic = characteristic.to_s
        to_precision = options[:precision] || precision
        mantissa = to_precision.positive? ? format("%0#{to_precision}d", mantissa) : nil

        characteristic = characteristic.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse if options[:commatize]

        [negative? ? '-' : nil, characteristic, mantissa ? '.' : nil, mantissa].compact.join
      end

      def quantity_as_bigdecimal
        BigDecimal quantity_as_s
      end

      # This returns the characteristic and mantissa for our quantity, given our precision,
      # note that we do not return the +/- signage. That information is destroyed here
      def quantity_as_decimal_pair
        characteristic = quantity.abs.to_i / (10**precision)
        [characteristic, quantity.abs.to_i - (characteristic * (10**precision))]
      end

      def to_s(options = {})
        ret = [quantity_as_s(options)]
        if code && !options[:no_code]
          operand = code.count(' ').positive? ? ['"', code, '"'].join : code
          code.length == 1 ? ret.unshift(operand) : ret.push(operand)
        end
        ret.join(' ')
      end

      def to_f
        quantity_as_s.to_f
      end

      def positive?
        quantity.positive?
      end

      def negative?
        quantity.negative?
      end

      def invert!
        @quantity *= -1
        self
      end

      def abs
        RRA::Journal::Commodity.new code, alphabetic_code, quantity.abs, precision
      end

      def round_or_floor(to_digit)
        raise UnimplementedError unless to_digit >= 0

        characteristic, mantissa = quantity_as_decimal_pair

        new_characteristic = characteristic * (10**to_digit)
        new_mantissa = mantissa.positive? ? (mantissa / (10**(precision - to_digit))).to_i : 0

        new_quantity = new_characteristic + new_mantissa

        # Round up?
        if __callee__ == :round && mantissa.positive? && precision > to_digit
          # We want the determinant to be the right-most digit in the round_determinant, then we mod 10 that
          round_determinant = (mantissa / (10**(precision - to_digit - 1)) % 10).to_i

          new_quantity += 1 if round_determinant >= 5
        end

        RRA::Journal::Commodity.new code, alphabetic_code, positive? ? new_quantity : new_quantity * -1, to_digit
      end

      alias floor round_or_floor
      alias round round_or_floor

      %i[> < <=> >= <= == !=].each do |operation|
        define_method(operation) do |rvalue|
          assert_commodity rvalue

          lquantity, rquantity = quantities_denominated_against rvalue

          lquantity.send operation, rquantity
        end
      end

      %i[* /].each do |operation|
        define_method(operation) do |rvalue|
          result = if rvalue.is_a? Numeric
                     # These mul/divs are often "Divide by half" "Multiply by X" instructions
                     # for which the rvalue is not, and should not be, a commodity.
                     quantity_as_bigdecimal.send operation, rvalue
                   else
                     assert_commodity rvalue

                     raise UnimplementedError
                   end

          RRA::Journal::Commodity.from_symbol_and_amount code, result.round(MAX_DECIMAL_DIGITS).to_s('F')
        end
      end

      %i[+ -].each do |operation|
        define_method(operation) do |rvalue|
          assert_commodity rvalue

          lquantity, rquantity, dprecision = quantities_denominated_against rvalue

          result = lquantity.send operation, rquantity

          # Adjust the dprecision. Probably there's a better way to do this, but,
          # this works
          our_currency = RRA::Journal::Currency.from_code_or_symbol code

          # This is a special case:
          return RRA::Journal::Commodity.new code, alphabetic_code, result, our_currency.minor_unit if result.zero?

          # If we're trying to remove more digits than minor_unit, we have to adjust
          # our cut
          if our_currency && (dprecision > our_currency.minor_unit) && /\A.+?(0+)\Z/.match(result.to_s) &&
             ::Regexp.last_match(1)
            trim_length = ::Regexp.last_match(1).length
            dprecision -= trim_length

            if dprecision < our_currency.minor_unit
              add = our_currency.minor_unit - dprecision
              dprecision += add
              trim_length -= add
            end

            result /= 10**trim_length
          end

          RRA::Journal::Commodity.new code, alphabetic_code, result, dprecision
        end
      end

      # We're mostly/only using this to support [].sum atm
      def coerce(other)
        super unless other.is_a? Integer

        [RRA::Journal::Commodity.new(code, alphabetic_code, other, precision), self]
      end

      def respond_to_missing?(name, _include_private = false)
        @quantity.respond_to? name
      end

      def method_missing(name, *args, &blk)
        # This handles most all of the numeric methods
        if @quantity.respond_to?(name) && args.length == 1 && args[0].is_a?(self.class)
          assert_commodity args[0]

          unless commodity.precision == precision
            raise UnimplementedError, format('Unimplemented operation %s Wot do?', name.inspect)
          end

          RRA::Journal::Commodity.new code, alphabetic_code, @quantity.send(name, args[0].quantity, &blk), precision
        else
          super
        end
      end

      def self.from_s(str)
        commodity_parts_from_string str
      end

      def self.from_s_with_remainder(str)
        commodity_parts_from_string str, with_remainder: true
      end

      def self.from_symbol_and_amount(symbol, amount = 0)
        currency = RRA::Journal::Currency.from_code_or_symbol symbol
        precision, quantity = *precision_and_quantity_from_amount(amount)
        #   NOTE: Sometimes (say shares) we deal with fractions of a penny. If this
        #   is such a case, we preserve the larger precision
        if currency && currency.minor_unit > precision
          # This is a case where, say "$ 1" is passed. But, we want to store that
          # as 100
          quantity *= 10**(currency.minor_unit - precision)
          precision = currency.minor_unit
        end

        new symbol, currency ? currency.alphabetic_code : symbol, quantity, precision
      end

      def self.commodity_parts_from_string(string, opts = {})
        (opts[:with_remainder] ? MATCH_COMMODITY_WITH_REMAINDER : MATCH_COMMODITY_WITHOUT_REMAINDER).match string.to_s

        code, amount = if ::Regexp.last_match(1) && !::Regexp.last_match(1).empty?
                         [::Regexp.last_match(1),
                          [::Regexp.last_match(2), ::Regexp.last_match(3)].compact.reject(&:empty?).first]
                       elsif ::Regexp.last_match(4) && !::Regexp.last_match(4).empty?
                         [[::Regexp.last_match(5),
                           ::Regexp.last_match(6)].compact.reject(&:empty?).first, ::Regexp.last_match(4)]
                       elsif ::Regexp.last_match(2) && !::Regexp.last_match(2).empty?
                         [::Regexp.last_match(2),
                          [::Regexp.last_match(3), ::Regexp.last_match(4)].compact.reject(&:empty?).first]
                       end

        if !amount || !code || amount.empty? || code.empty?
          raise UnimplementedError, format('Unimplemented Commodity::from_s. Against: %s. Wot do?', string.inspect)
        end

        commodity = from_symbol_and_amount code, amount.tr(',', '')

        opts[:with_remainder] ? [commodity, ::Regexp.last_match(7)] : commodity
      end

      def self.precision_and_quantity_from_amount(amount)
        [amount.to_s.reverse.index('.') || 0, amount.to_s.tr('.', '').to_i]
      end

      private

      # This returns our quantity, and rvalue.quantity, after adjusting both
      # to the largest of the two denominators
      def quantities_denominated_against(rvalue)
        lquantity = quantity
        rquantity = rvalue.quantity
        new_precision = precision

        if precision > rvalue.precision
          new_precision = precision
          rquantity = rvalue.quantity * (10**(precision - rvalue.precision))
        elsif precision < rvalue.precision
          new_precision = rvalue.precision
          lquantity = quantity * (10**(rvalue.precision - precision))
        end

        [lquantity, rquantity, new_precision]
      end

      def assert_commodity(commodity)
        our_codes = [alphabetic_code, code]

        unless our_codes.include?(commodity.alphabetic_code)
          raise ConversionError, format('Provided commodity %<commodity>s does not match %<codes>s',
                                        commodity: commodity.inspect,
                                        codes: our_codes.inspect)
        end
      end
    end
  end
end
