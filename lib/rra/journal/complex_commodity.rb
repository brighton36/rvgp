# These 'complex currency' specifications appear to be mostly for non-register
# and non-balance reports. Which, we really don't use. I'm not entirely sure
# the parsing rules make sense. And some of the rules in the documentation even
# seem a bit inconsistent (see complex expressions vs comments).
#
# We ended up needing most of this to run a dupe-tag check. And to ensure that
# we're able to mostly-validate the syntax of the journals. We don't actually
# use many code paths here, otherwise. (Though we do use it to serialize 
# currency conversion in the file_transform_investment.rb)
# 
# I'm not entirely sure what attribute names to use. We could go with intent
# position, or with class. Either path seems to introduce exceptions. Possibly
# some of these attributes should just go into the transfer class. I'm also not
# sure that the left_/right_/operation system makes sense.
#
# I also think we need some adjustments here to cover all parsing cases. But,
# for now this works well enough, again mostly because we're not using most 
# of these code paths... Lets see if/how this evolves.
class RRA::Journal::ComplexCommodity
  LOT_MATCH = /\A(\{+)[ ]*([\=]?)[ ]*([^\}]+)\}+(.*)\Z/
  LAMBDA_MATCH = /\A\(\((.+)\)\)(.*)\Z/
  OP_MATCH = /\A(\@{1,2})(.*)\Z/
  WHITESPACE_MATCH = /\A[ \t]+(.*)\Z/
  EQUAL_MATCH = /\A\=(.*)\Z/

  DATE_MATCH = /\A\[([\d]{4})\-([\d]{1,2})\-([\d]{1,2})\](.*)\Z/
  COMMENT_MATCH = /\A\(([^\)]+)\)(.*)\Z/
  MSG_TOO_MANY = 'Too many %s in ComplexCommodity::from_s. Against: %s'
  MSG_UNPARSEABLE = 'The ComplexCommodity::from_s "%s" appears to be unparseable'

  ATTRIBUTES = %w(left right operation left_date left_lot left_lot_operation
    left_lot_is_equal left_expression right_expression left_lambda left_is_equal
    right_is_equal)

  attr_reader *ATTRIBUTES.collect(&:to_sym)

  class Error < StandardError; end

  def initialize(opts = {})
    ATTRIBUTES.select{|attr| opts.has_key? attr.to_sym}.each do |attr| 
      instance_variable_set(('@%s' % attr).to_sym, opts[attr.to_sym])
    end
  end

  # For now, we simply delegate these messages to the left commodity. This path
  # is only in use in the transformer, which, determines whether the commodity
  # is income or expense. (and/or inverts the amount) It's conceivable that we 
  # may want to test the right commodity at some point here, and determine if 
  # the net operation is positive or negative.
  def positive?; left.positive?; end
  def invert!; left.invert!; self; end

  def to_s
    [ 
    (left_is_equal) ? '=' : nil,
    (left) ? left.to_s : nil,
    (left_lot_operation and left_lot) ? 
    ( ((left_lot_operation == :per_unit) ? '{%s}' : '{{%s}}') % [
      left_lot_is_equal ? '=' : nil, left_lot.to_s].compact.join ) : nil,
    (left_date) ? '[%s]' % left_date.to_s : nil,
    (left_expression) ? '(%s)' % left_expression.to_s : nil,
    (left_lambda) ? '((%s))' % left_lambda.to_s : nil,
    (operation) ? ( (operation == :per_unit) ? '@' : '@@') : nil,
    (right_is_equal) ? '=' : nil,
    (right) ? right.to_s : nil,
    (right_expression) ? '(%s)' % right_expression.to_s : nil
    ].compact.join(' ')
  end

  def self.from_s(string)
    tmp = string.dup
    opts = {}

    # We treat string like a kind of stack, and we pop off what we can parse 
    # from the left, heading to the right
    while tmp.length > 0
      case tmp
        when WHITESPACE_MATCH
          tmp = $1
        when EQUAL_MATCH
          side = (opts[:operation]) ? :right_is_equal : :left_is_equal
          ensure_not_too_many! opts, side, string
          opts[side], tmp = true, $1
        when LOT_MATCH
          ensure_not_too_many! opts, :left_lot, string
          opts[:left_lot_operation] = to_operator $1
          opts[:left_lot_is_equal] = ($2 == '=')
          opts[:left_lot] = $3.to_commodity
          tmp = $4
        when LAMBDA_MATCH
          ensure_not_too_many! opts, :left_lambda, string
          opts[:left_lambda] = $1
          tmp = $2
        when DATE_MATCH
          ensure_not_too_many! opts, :left_date, string
          opts[:left_date] = Date.new $1.to_i, $2.to_i, $3.to_i
          tmp = $4
        when OP_MATCH
          ensure_not_too_many! opts, :operation, string
          opts[:operation] = to_operator $1
          tmp = $2
        when COMMENT_MATCH
          side = (opts[:operation]) ? :right_expression : :left_expression
          ensure_not_too_many! opts, side, string
          opts[side], tmp = $1, $2
        else
          begin
            commodity, tmp = RRA::Journal::Commodity::from_s_with_remainder tmp
          rescue RRA::Journal::Commodity::Error
            raise Error, MSG_UNPARSEABLE % string
          end

          side = (opts[:operation]) ? :right : :left
          ensure_not_too_many! opts, side, string
          opts[side] = commodity
      end
    end

    self.new opts
  end

  def self.to_operator(from_s)
    case from_s
      when '@'  then :per_unit
      when '@@' then :per_lot
      when '{'  then :per_unit
      when '{{' then :per_lot
      else
        raise Error, "Unrecognized operator %s" % from_s.inspect
    end
  end

  private

  # This mostly just saves us some typing above in the from_s()
  def self.ensure_not_too_many!(opts, key, string)
    raise Error, MSG_TOO_MANY % [key.to_s, string] if opts.has_key? key
  end
end
