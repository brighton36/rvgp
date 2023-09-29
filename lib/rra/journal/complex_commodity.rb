# frozen_string_literal: true

module RRA
  class Journal
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
    #
    # @attr_reader [String] left The 'left' component of the complex commodity
    # @attr_reader [String] right The 'right' component of the complex commodity
    # @attr_reader [Symbol] operation The 'operation' component of the complex commodity, either :right_expression,
    #                                 :left_expression, :per_unit, or :per_lot
    # @attr_reader [Date] left_date The 'left_date' component of the complex commodity
    # @attr_reader [String] left_lot The 'left_lot' component of the complex commodity
    # @attr_reader [Symbol] left_lot_operation The 'left_lot_operation' component of the complex commodity, either
    #                                          :per_unit, or :per_lot
    # @attr_reader [TrueClass, FalseClass] left_lot_is_equal The 'left_lot_is_equal' component of the complex
    #                                                        commodity
    # @attr_reader [String] left_expression The 'left_expression' component of the complex commodity
    # @attr_reader [String] right_expression The 'right_expression' component of the complex commodity
    # @attr_reader [String] left_lambda The 'left_lambda' component of the complex commodity
    # @attr_reader [TrueClass, FalseClass] left_is_equal The 'left_is_equal' component of the complex commodity
    # @attr_reader [TrueClass, FalseClass] right_is_equal The 'right_is_equal' component of the complex commodity
    class ComplexCommodity
      LOT_MATCH = /\A(\{+) *(=?) *([^}]+)\}+(.*)\Z/.freeze
      LAMBDA_MATCH = /\A\(\((.+)\)\)(.*)\Z/.freeze
      OP_MATCH = /\A(@{1,2})(.*)\Z/.freeze
      WHITESPACE_MATCH = /\A[ \t]+(.*)\Z/.freeze
      EQUAL_MATCH = /\A=(.*)\Z/.freeze

      DATE_MATCH = /\A\[(\d{4})-(\d{1,2})-(\d{1,2})\](.*)\Z/.freeze
      COMMENT_MATCH = /\A\(([^)]+)\)(.*)\Z/.freeze
      MSG_TOO_MANY = 'Too many %s in ComplexCommodity::from_s. Against: %s'
      MSG_UNPARSEABLE = 'The ComplexCommodity::from_s "%s" appears to be unparseable'

      ATTRIBUTES = %i[left right operation left_date left_lot left_lot_operation left_lot_is_equal left_expression
                      right_expression left_lambda left_is_equal right_is_equal].freeze

      # @!visibility protected
      attr_reader(*ATTRIBUTES) # :nodoc:

      class Error < StandardError; end

      def initialize(opts = {})
        ATTRIBUTES.select { |attr| opts.key? attr }.each do |attr|
          instance_variable_set("@#{attr}".to_sym, opts[attr])
        end
      end

      # For now, we simply delegate these messages to the left commodity. This path
      # is only in use in the transformer, which, determines whether the commodity
      # is income or expense. (and/or inverts the amount) It's conceivable that we
      # may want to test the right commodity at some point here, and determine if
      # the net operation is positive or negative.
      def positive?
        left.positive?
      end

      def invert!
        left.invert!
        self
      end

      def to_s
        [left_is_equal ? '=' : nil,
         left ? left.to_s : nil,
         if left_lot_operation && left_lot
           format(left_lot_operation == :per_unit ? '{%s}' : '{{%s}}',
                  *[left_lot_is_equal ? '=' : nil, left_lot.to_s].compact.join)
         end,
         left_date ? format('[%s]', left_date.to_s) : nil,
         left_expression ? format('(%s)', left_expression.to_s) : nil,
         left_lambda ? format('((%s))', left_lambda.to_s) : nil,
         if operation
           operation == :per_unit ? '@' : '@@'
         end,
         right_is_equal ? '=' : nil,
         right ? right.to_s : nil,
         right_expression ? format('(%s)', right_expression.to_s) : nil].compact.join(' ')
      end

      def self.from_s(string)
        tmp = string.dup
        opts = {}

        # We treat string like a kind of stack, and we pop off what we can parse
        # from the left, heading to the right
        until tmp.empty?
          case tmp
          when WHITESPACE_MATCH
            tmp = ::Regexp.last_match(1)
          when EQUAL_MATCH
            side = opts[:operation] ? :right_is_equal : :left_is_equal
            ensure_not_too_many! opts, side, string
            opts[side] = true
            tmp = ::Regexp.last_match(1)
          when LOT_MATCH
            ensure_not_too_many! opts, :left_lot, string
            opts[:left_lot_operation] = to_operator ::Regexp.last_match(1)
            opts[:left_lot_is_equal] = (::Regexp.last_match(2) == '=')
            opts[:left_lot] = ::Regexp.last_match(3).to_commodity
            tmp = ::Regexp.last_match(4)
          when LAMBDA_MATCH
            ensure_not_too_many! opts, :left_lambda, string
            opts[:left_lambda] = ::Regexp.last_match(1)
            tmp = ::Regexp.last_match(2)
          when DATE_MATCH
            ensure_not_too_many! opts, :left_date, string
            opts[:left_date] = Date.new(*(1..3).map { |i| ::Regexp.last_match(i).to_i })
            tmp = ::Regexp.last_match(4)
          when OP_MATCH
            ensure_not_too_many! opts, :operation, string
            opts[:operation] = to_operator ::Regexp.last_match(1)
            tmp = ::Regexp.last_match(2)
          when COMMENT_MATCH
            side = opts[:operation] ? :right_expression : :left_expression
            ensure_not_too_many! opts, side, string
            opts[side] = ::Regexp.last_match(1)
            tmp = ::Regexp.last_match(2)
          else
            begin
              commodity, tmp = RRA::Journal::Commodity.from_s_with_remainder tmp
            rescue RRA::Journal::Commodity::Error
              raise Error, MSG_UNPARSEABLE % string
            end

            side = opts[:operation] ? :right : :left
            ensure_not_too_many! opts, side, string
            opts[side] = commodity
          end
        end

        new opts
      end

      def self.to_operator(from_s)
        case from_s
        when /\A[@{]\Z/ then :per_unit
        when /\A(?:@@|{{)\Z/ then :per_lot
        else
          raise Error, format('Unrecognized operator %s', from_s.inspect)
        end
      end

      # This mostly just saves us some typing above in the from_s()
      def self.ensure_not_too_many!(opts, key, string)
        raise Error, format(MSG_TOO_MANY, key.to_s, string) if opts.key? key
      end
    end
  end
end
