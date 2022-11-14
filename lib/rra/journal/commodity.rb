require 'bigdecimal'
require 'pry'

class RRA::Journal::Commodity
  attr_accessor :quantity, :code, :alphabetic_code, :precision

  MATCH_AMOUNT = '([-]?[ ]*?[\d\,]+(?:\\.[\d]+|))'
  MATCH_CODE = '(?:(?<!\\\\)\"(.+)(?<!\\\\)\"|([^ \-\d]+))'
  MATCH_COMMODITY = ['\\A(?:',
    MATCH_CODE,'[ ]*?',MATCH_AMOUNT,'|',
    MATCH_AMOUNT,'[ ]*?',MATCH_CODE ]

  MATCH_COMMODITY_WITHOUT_REMAINDER = Regexp.new((MATCH_COMMODITY+[')\\Z']).join)
  MATCH_COMMODITY_WITH_REMAINDER = Regexp.new((MATCH_COMMODITY+[')(.*?)\\Z']).join)

  # This appears to be a ruby limit, in float's
  MAX_DECIMAL_DIGITS = 17

  class ConversionError < StandardError; end
  class UnimplementedError < StandardError; end

  def initialize(code, alphabetic_code, quantity, precision)
    @code, @alphabetic_code, @quantity, @precision = code, alphabetic_code, 
      quantity.to_i, precision.to_i
  end

  def quantity_as_s(options = {})
    characteristic, mantissa = (options.has_key? :precision) ?
      round(options[:precision]).quantity_as_decimal_pair :
      quantity_as_decimal_pair

    characteristic = characteristic.to_s
    to_precision = options[:precision] || precision
    mantissa = (to_precision > 0) ? "%0#{to_precision}d" % mantissa : nil

    characteristic = characteristic.reverse.gsub(/(\d{3})(?=\d)/, 
      '\\1,').reverse if options[:commatize] 

    [ (negative?) ? '-' : nil, characteristic, (mantissa) ? '.' : nil,
      mantissa].compact.join
  end

  def quantity_as_bigdecimal
    BigDecimal quantity_as_s
  end
  
  # This returns the characteristic and mantissa for our quantity, given our precision,
  # note that we do not return the +/- signage. That information is destroyed here
  def quantity_as_decimal_pair
    characteristic = quantity.abs.to_i / 10**precision
    [characteristic, quantity.abs.to_i - characteristic*10**precision]
  end


  def to_s(options = {})
    ret = [quantity_as_s(options)]
    ret.send( (code.length == 1) ? :unshift : :push, 
      (code.count(' ') > 0) ? ['"', code, '"'].join : code
    ) unless options[:no_code]
    ret.join(' ')
  end

  def to_f; quantity_as_s.to_f; end

  def positive?; quantity > 0; end
  def negative?; quantity < 0; end
  
  def invert!; @quantity *= -1; self; end

  def abs
    RRA::Journal::Commodity.new code, alphabetic_code, quantity.abs, precision
  end

  def round_or_floor(to_digit)
    raise UnimplementedError unless to_digit >= 0

    characteristic, mantissa = quantity_as_decimal_pair

    new_characteristic = characteristic * 10**(to_digit)
    new_mantissa = (mantissa > 0) ? 
      (mantissa / 10**(precision - to_digit)).to_i : 0

    new_quantity = new_characteristic+new_mantissa

    # Round up?
    if (__callee__ == :round) and (mantissa > 0)
      if precision > to_digit
        # We want the determinant to be the right-most digit in the round_determinant, then we mod 10 that
        round_determinant = ( mantissa / (10**(precision-to_digit-1)) % 10).to_i

        new_quantity += 1 if round_determinant >= 5
      end
    end

    RRA::Journal::Commodity.new code, alphabetic_code,
      (positive?) ? new_quantity : new_quantity*-1 , to_digit
  end

  alias :floor :round_or_floor
  alias :round :round_or_floor

  [:>, :<, :<=>, :>=, :<=, :==, :!=].each do |operation|
    define_method(operation) do |rvalue|
      assert_commodity rvalue

      lquantity, rquantity = quantities_denominated_against rvalue

      lquantity.send operation, rquantity
    end
  end

  [:*, :/].each do |operation|
    define_method(operation) do |rvalue|
      result = if rvalue.kind_of? Numeric
        # These mul/divs are often "Divide by half" "Multiply by X" instructions
        # for which the rvalue is not, and should not be, a commodity.
        quantity_as_bigdecimal.send operation, rvalue
      else
        assert_commodity rvalue 

        raise UnimplementedError
      end

      RRA::Journal::Commodity.from_symbol_and_amount code, 
        result.round(MAX_DECIMAL_DIGITS).to_s('F')
    end
  end

  [:+, :-].each do |operation|
    define_method(operation) do |rvalue|
      assert_commodity rvalue
      
      lquantity, rquantity, dprecision = quantities_denominated_against rvalue
       
      result = lquantity.send operation, rquantity

      # Adjust the dprecision. Probably there's a better way to do this, but,
      # this works
      our_currency = RRA::Journal::Currency.from_code_or_symbol code

      # This is a special case:
      return RRA::Journal::Commodity.new(code, alphabetic_code, result, 
        our_currency.minor_unit) if result == 0 

      # If we're trying to remove more digits than minor_unit, we have to adjust
      # our cut
      if our_currency and (dprecision > our_currency.minor_unit) and 
        /\A(.+?)(0+)\Z/.match(result.to_s) and $2
        retain_length = $1.length
        trim_length = $2.length
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
    super unless other.kind_of? Integer 

    [RRA::Journal::Commodity.new(code, alphabetic_code, other, precision), self]
  end

  def method_missing(name, *args, &blk)
    # This handles most all of the numeric methods
    if [@quantity.respond_to?(name), (args.length == 1), 
      args[0].kind_of?(self.class)].all?

      assert_commodity args[0]

      unless commodity.precision == precision
        raise UnimplementedError, "Unimplemented operation %s Wot do?" % name.inspect 
      end

      RRA::Journal::Commodity.new code, alphabetic_code, 
        @quantity.send(name, args[0].quantity, &blk), precision
    else
      super
    end
  end

  def self.from_s(s)
    commodity_parts_from_string s
  end

  def self.from_s_with_remainder(s)
    commodity_parts_from_string s, with_remainder: true
  end
  
  def self.from_symbol_and_amount(symbol, amount = 0)
    currency = RRA::Journal::Currency.from_code_or_symbol symbol
    precision, quantity = *precision_and_quantity_from_amount(amount)
    #   NOTE: Sometimes (say shares) we deal with fractions of a penny. If this
    #   is such a case, we preserve the larger precision
    if currency and currency.minor_unit > precision
      # This is a case where, say "$ 1" is passed. But, we want to store that
      # as 100
      quantity *= 10**(currency.minor_unit-precision)
      precision = currency.minor_unit
    end

    self.new symbol, (currency) ? currency.alphabetic_code : symbol, quantity, 
      precision
  end

  private

  def self.commodity_parts_from_string(string, opts = {})
    ( (opts[:with_remainder]) ? MATCH_COMMODITY_WITH_REMAINDER :
        MATCH_COMMODITY_WITHOUT_REMAINDER ).match string.to_s

    code, amount = if $1 and !$1.empty?
      [ $1, [$2, $3].compact.reject(&:empty?).first ]
    elsif $4 and !$4.empty?
      [[$5, $6].compact.reject(&:empty?).first, $4 ]
    elsif $2 and !$2.empty?
      [ $2, [$3, $4].compact.reject(&:empty?).first ]
    end

    raise UnimplementedError, 
      "Unimplemented Commodity::from_s. Against: %s. Wot do?" % [
        string.inspect ] if !amount or !code or amount.empty? or code.empty?

    commodity = from_symbol_and_amount code, amount.tr(',', '')

    return (opts[:with_remainder]) ? [commodity, $7] : commodity
  end

  # This returns our quantity, and rvalue.quantity, after adjusting both
  # to the largest of the two denominators
  def quantities_denominated_against(rvalue)
    lquantity = quantity
    rquantity = rvalue.quantity
    new_precision = precision

    if precision > rvalue.precision
      new_precision = precision
      rquantity = rvalue.quantity*10**(precision - rvalue.precision)
    elsif precision < rvalue.precision
      new_precision = rvalue.precision
      lquantity = quantity*10**(rvalue.precision - precision)
    end
    
    [lquantity, rquantity, new_precision]
  end

  def assert_commodity(commodity)
    our_codes = [alphabetic_code, code] 

    raise ConversionError, "Provided commodity %s does not match %s" % [
      commodity.inspect, our_codes.inspect
    ] unless our_codes.include?(commodity.alphabetic_code)
  end

  def self.precision_and_quantity_from_amount(amount)
    [ amount.to_s.reverse.index('.') || 0, amount.to_s.tr('.', '').to_i ]
  end
end
