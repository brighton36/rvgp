# frozen_string_literal: true

require 'bigdecimal'

module RVGP
  class Journal
    # This abstraction defines a simple commodity entry, as would be found in a pta journal.
    # Such commodities can appear in the form of currency, such as '$ 1.30' or in any other
    # format that hledger and ledger parse. ie '1 HOUSE'.
    #
    # There's a lot of additional functionality provided by this class, including math
    # related helper functions.
    #
    # NOTE: the easiest way to create a commodity in your code, is by way of the
    # provided {String#to_commodity} method. Such as: '$ 1.30'.to_commodity.
    #
    # Units of a commodity are stored in int's, with precision. This ensures that
    # there is no potential for floating point precision errors, affecting these
    # commodities.
    #
    # A number of constants, relating to the built-in support of various currencies, are
    # available as part of RVGP, in the form of the
    # {https://github.com/brighton36/rra/blob/main/resources/iso-4217-currencies.json iso-4217-currencies.json}
    # file. Which, is loaded automatically during initialization.
    #
    # @attr_reader [String] code The code of this commodity. Which, may be the same as :alphabetic_code, or, may take
    #                            the form of symbol. (ie '$'). This code is used to render the commodity to strings.
    # @attr_reader [String] alphabetic_code The ISO-4217 'Alphabetic Code' of this commodity. This code is used for
    #                                       various non-rendering functions. (Equality testing, Conversion lookups...)
    # @attr_reader [Integer] quantity The number of units, of this currency, before applying a fractional representation
    #                                 (Ie "$ 2.89" is stored in the form of :quantity 289)
    # @attr_reader [Integer] precision The exponent of the characteristic, which is used to separate the mantissa
    #                                  from the significand.
    class Commodity
      attr_accessor :quantity, :code, :alphabetic_code, :precision

      # @!visibility private
      MATCH_AMOUNT = '([-]?[ ]*?[\d\,]+(?:\\.[\d]+|))'

      # @!visibility private
      MATCH_CODE = '(?:(?<!\\\\)\"(.+)(?<!\\\\)\"|([^ \-\d]+))'

      # @!visibility private
      MATCH_COMMODITY = ['\\A(?:', MATCH_CODE, '[ ]*?', MATCH_AMOUNT, '|', MATCH_AMOUNT, '[ ]*?', MATCH_CODE].freeze

      # @!visibility private
      MATCH_COMMODITY_WITHOUT_REMAINDER = Regexp.new((MATCH_COMMODITY + [')\\Z']).join)

      # @!visibility private
      MATCH_COMMODITY_WITH_REMAINDER = Regexp.new((MATCH_COMMODITY + [')(.*?)\\Z']).join)

      # This appears to be a ruby limit, in float's
      # @!visibility private
      MAX_DECIMAL_DIGITS = 17

      # This error is typically thrown when a commodity is evaluated against an rvalue that doesn't
      # match the commodity of the lvalue.
      class ConversionError < StandardError; end

      # There are a handful of code paths that are currently unimplemented. Usually these are
      # unimplemented because the interpretation of the request is ambiguous.
      class UnimplementedError < StandardError; end

      # Create a commodity, from the constituent parts
      # @param [String] code see {Commodity#code}
      # @param [String] alphabetic_code see {Commodity#alphabetic_code}
      # @param [Integer] quantity see {Commodity#quantity}
      # @param [Integer] precision see {Commodity#precision}
      def initialize(code, alphabetic_code, quantity, precision)
        @code = code
        @alphabetic_code = alphabetic_code
        @quantity = quantity.to_i
        @precision = precision.to_i
      end

      # Render the :quantity, to a string. This is output without code notation, and merely
      # expressed the quantity with the expected symbols (commas, periods) .
      # @param [Hash] options formatting specifiers, affecting what output is produced
      # @option options [Integer] precision Use the provided precision, instead of the :precision accessor
      # @option options [TrueClass,FalseClass] commatize (false) Whether or not to insert commas in the output, between
      #                                                  every three digits, in the characteristic
      # @return [String] The formatted quantity
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

      # Returns the quantity component of the commodity, as a BigDecimal
      # @return [BigDecimal]
      def quantity_as_bigdecimal
        BigDecimal quantity_as_s
      end

      # This returns the characteristic and mantissa for our quantity, given our precision,
      # note that we do not return the +/- signage. That information is destroyed here
      # @return [Array<Integer>] A two-value array, with characteristic at [0], and fraction at [1]
      def quantity_as_decimal_pair
        characteristic = quantity.abs.to_i / (10**precision)
        [characteristic, quantity.abs.to_i - (characteristic * (10**precision))]
      end

      # Render the commodity to a string, in the form it would appear in a journal. This output
      # includes the commodity code, as well as a period and, optionally commas.
      # @param [Hash] options formatting specifiers, affecting what output is produced
      # @option options [Integer] precision Use the provided precision, instead of the :precision accessor
      # @option options [TrueClass,FalseClass] commatize (false) Whether or not to insert commas in the output, between
      #                                                  every three digits, in the characteristic
      # @option options [TrueClass,FalseClass] no_code (false) If true, the code is omitted in the output
      # @return [String] The formatted quantity
      def to_s(options = {})
        ret = [quantity_as_s(options)]
        if code && !options[:no_code]
          operand = code.count(' ').positive? ? ['"', code, '"'].join : code
          code.length == 1 ? ret.unshift(operand) : ret.push(operand)
        end
        ret.join(' ')
      end

      # Returns the quantity component of the commodity, after being adjusted for :precision, as a Float. Consider
      # using {#quantity_as_bigdecimal} instead.
      # @return [Float]
      def to_f
        quantity_as_s.to_f
      end

      # Returns whether or not the quantity is greater than zero.
      # @return [TrueClass,FalseClass] yes or no
      def positive?
        quantity.positive?
      end

      # Returns whether or not the quantity is less than zero.
      # @return [TrueClass,FalseClass] yes or no
      def negative?
        quantity.negative?
      end

      # Multiply the quantity by -1. This mutates the state of self.
      # @return [RVGP::Journal::Commodity] self, after the transformation is applied
      def invert!
        @quantity *= -1
        self
      end

      # Returns a copy of the current Commodity, with the absolute value of quanity.
      # @return [RVGP::Journal::Commodity] self, with quantity.abs applied
      def abs
        RVGP::Journal::Commodity.new code, alphabetic_code, quantity.abs, precision
      end

      # This method returns a new Commodity, with :floor applied to its :quantity.
      # @param [Integer] to_digit Which digit to floor to
      # @return [RVGP::Journal::Commodity] A new copy of self, with quantity :floor'd
      def floor(to_digit)
        round_or_floor to_digit, :floor
      end

      # This method returns a new Commodity, with :round applied to its :quantity.
      # @param [Integer] to_digit Which digit to round to
      # @return [RVGP::Journal::Commodity] A new copy of self, with quantity :rounded
      def round(to_digit)
        round_or_floor to_digit, :round
      end

      # @!method >(rvalue)
      # Ensure that rvalue is a commodity. Then return a boolean indicating whether self.quantity
      # is greater than rvalue's quantity.
      # @param [RVGP::Journal::Commodity] rvalue Another commodity to compare our quantity to
      # @return [TrueClass,FalseClass] Result of comparison.

      # @!method <(rvalue)
      # Ensure that rvalue is a commodity. Then return a boolean indicating whether self.quantity
      # is less than rvalue's quantity.
      # @param [RVGP::Journal::Commodity] rvalue Another commodity to compare our quantity to
      # @return [TrueClass,FalseClass] Result of comparison.

      # @!method <=>(rvalue)
      # Ensure that rvalue is a commodity. Then returns an integer indicating whether self.quantity
      # is (spaceship) rvalue's quantity. More specifically: -1 on <, 0 on ==, 1 on >.
      # @param [RVGP::Journal::Commodity] rvalue Another commodity to compare our quantity to
      # @return [Integer] Result of comparison: -1, 0, or 1.

      # @!method >=(rvalue)
      # Ensure that rvalue is a commodity. Then return a boolean indicating whether self.quantity
      # is greater than or equal to rvalue's quantity.
      # @param [RVGP::Journal::Commodity] rvalue Another commodity to compare our quantity to
      # @return [TrueClass,FalseClass] Result of comparison.

      # @!method <=(rvalue)
      # Ensure that rvalue is a commodity. Then return a boolean indicating whether self.quantity
      # is less than or equal to rvalue's quantity.
      # @param [RVGP::Journal::Commodity] rvalue Another commodity to compare our quantity to
      # @return [TrueClass,FalseClass] Result of comparison.

      # @!method ==(rvalue)
      # Ensure that rvalue is a commodity. Then return a boolean indicating whether self.quantity
      # is equal to rvalue's quantity.
      # @param [RVGP::Journal::Commodity] rvalue Another commodity to compare our quantity to
      # @return [TrueClass,FalseClass] Result of comparison.

      # @!method !=(rvalue)
      # Ensure that rvalue is a commodity. Then return a boolean indicating whether self.quantity
      # is not equal to rvalue's quantity.
      # @param [RVGP::Journal::Commodity] rvalue Another commodity to compare our quantity to
      # @return [TrueClass,FalseClass] Result of comparison.
      %i[> < <=> >= <= == !=].each do |operation|
        define_method(operation) do |rvalue|
          assert_commodity rvalue

          lquantity, rquantity = quantities_denominated_against rvalue

          lquantity.send operation, rquantity
        end
      end

      # @!method *(rvalue)
      # If the rvalue is a commodity, assert that we share the same commodity code, and if so
      # multiple our quantity by the rvalue quantity. If rvalue is numeric, multiply our quantity
      # by this numeric.
      # @param [RVGP::Journal::Commodity,Numeric] rvalue A multiplicand
      # @return [RVGP::Journal::Commodity] A new Commodity, composed of self.code, and the resulting quantity

      # @!method /(rvalue)
      # If the rvalue is a commodity, assert that we share the same commodity code, and if so
      # divide our quantity by the rvalue quantity. If rvalue is numeric, divide our quantity
      # by this numeric.
      # @param [RVGP::Journal::Commodity,Numeric] rvalue A divisor
      # @return [RVGP::Journal::Commodity] A new Commodity, composed of self.code, and the resulting quantity
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

          RVGP::Journal::Commodity.from_symbol_and_amount code, result.round(MAX_DECIMAL_DIGITS).to_s('F')
        end
      end

      # @!method +(rvalue)
      # If the rvalue is a commodity, assert that we share the same commodity code, and if so
      # sum our quantity with the rvalue quantity.
      # @param [RVGP::Journal::Commodity] rvalue An operand
      # @return [RVGP::Journal::Commodity] A new Commodity, composed of self.code, and the resulting quantity

      # @!method -(rvalue)
      # If the rvalue is a commodity, assert that we share the same commodity code, and if so
      # subtract the rvalue quantity from our quantity.
      # @param [RVGP::Journal::Commodity] rvalue An operand
      # @return [RVGP::Journal::Commodity] A new Commodity, composed of self.code, and the resulting quantity
      %i[+ -].each do |operation|
        define_method(operation) do |rvalue|
          assert_commodity rvalue

          lquantity, rquantity, dprecision = quantities_denominated_against rvalue

          result = lquantity.send operation, rquantity

          # Adjust the dprecision. Probably there's a better way to do this, but,
          # this works
          our_currency = RVGP::Journal::Currency.from_code_or_symbol code

          # This is a special case:
          return RVGP::Journal::Commodity.new code, alphabetic_code, result, our_currency.minor_unit if result.zero?

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

          RVGP::Journal::Commodity.new code, alphabetic_code, result, dprecision
        end
      end

      # We're mostly/only using this to support [].sum atm
      def coerce(other)
        super unless other.is_a? Integer

        [RVGP::Journal::Commodity.new(code, alphabetic_code, other, precision), self]
      end

      def respond_to_missing?(name, _include_private = false)
        @quantity.respond_to? name
      end

      # If an unhandled methods is encountered between ourselves, and another commodity,
      # we dispatch that method to the quantity of self, against the quantity of the
      # provided commodity.
      # @overload method_missing(attr, rvalue)
      #   @param [Symbol] attr An unhandled method
      #   @param [RVGP::Journal::Commodity] rvalue The operand
      #   @return [RVGP::Journal::Commodity] A new Commodity object, created using our code, and the resulting quantity.
      def method_missing(name, *args, &blk)
        # This handles most all of the numeric methods
        if @quantity.respond_to?(name) && args.length == 1 && args[0].is_a?(self.class)
          assert_commodity args[0]

          unless commodity.precision == precision
            raise UnimplementedError, format('Unimplemented operation %s Wot do?', name.inspect)
          end

          RVGP::Journal::Commodity.new code, alphabetic_code, @quantity.send(name, args[0].quantity, &blk), precision
        else
          super
        end
      end

      # Given a string, such as "$ 20.57", or "1 MERCEDESBENZ", Construct and return a commodity representation
      # @param [String] str The commodity, as would be found in a PTA journal
      # @return [RVGP::Journal::Commodity]
      def self.from_s(str)
        commodity_parts_from_string str
      end

      # @!visibility private
      # This parses a commodity in the same way that from_s parses, but, returns the strin that remains after the
      # commodity. Mostly this is here to keep ComplexCommodity DRY. Probably you shouldn't use this method
      # @return [Array<RVGP::Journal::Commodity, String>] A two element array, containing a commodity, and the unparsed
      #                                                  string, that remained after the commodity.
      def self.from_s_with_remainder(str)
        commodity_parts_from_string str, with_remainder: true
      end

      # Given a code, or symbol, and a quantity - Construct and return a commodity representation.
      # @param [String] symbol The commodity code, or symbol, as would be found in a PTA journal
      # @param [Integer, String] amount The commodity quantity. If this is a string, we search for periods, and
      #                                 calculate precision. If this is an int, we assume a precision based on
      #                                 the commodity code.
      # @return [RVGP::Journal::Commodity]
      def self.from_symbol_and_amount(symbol, amount = 0)
        currency = RVGP::Journal::Currency.from_code_or_symbol symbol
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

      # @!visibility private
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

      # @!visibility private
      def self.precision_and_quantity_from_amount(amount)
        [amount.to_s.reverse.index('.') || 0, amount.to_s.tr('.', '').to_i]
      end

      private

      def round_or_floor(to_digit, function)
        raise UnimplementedError unless to_digit >= 0

        characteristic, mantissa = quantity_as_decimal_pair

        new_characteristic = characteristic * (10**to_digit)
        new_mantissa = mantissa.positive? ? (mantissa / (10**(precision - to_digit))).to_i : 0

        new_quantity = new_characteristic + new_mantissa

        # Round up?
        if function == :round && mantissa.positive? && precision > to_digit
          # We want the determinant to be the right-most digit in the round_determinant, then we mod 10 that
          round_determinant = (mantissa / (10**(precision - to_digit - 1)) % 10).to_i

          new_quantity += 1 if round_determinant >= 5
        end

        RVGP::Journal::Commodity.new code, alphabetic_code, positive? ? new_quantity : new_quantity * -1, to_digit
      end

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
