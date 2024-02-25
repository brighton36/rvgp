# frozen_string_literal: true

require 'json'

module RRA
  class Journal
    # This abstraction offers a repository by which currencies can be defined,
    # and by which their rules can be queried. An instance of this class, is an
    # entry in the currency table, that we support. The default currencies that RRA
    # supports can be found in:
    # {https://github.com/brighton36/rra/blob/main/resources/iso-4217-currencies.json iso-4217-currencies.json}
    # , and this file is typically loaded during rra initialization.
    #
    # Here's what an entry in that file, looks like:
    #
    #  {
    #    "Entity":"UNITED STATES",
    #    "Currency":"US Dollar",
    #    "Alphabetic Code":"USD",
    #    "Numeric Code":"840",
    #    "Minor unit":"2",
    #    "Symbol":"$"
    #  },
    #
    # PR's welcome, if you have additions to offer on this file.
    #
    # This class is used in several places throughout the codebase, and provides
    # a standard set of interfaces for working with this global repository of
    # currency properties.
    # @attr_reader [String] entity The name of the institution to which this currency belongs. For some reason
    #                              (I believe this is part of the ISO-4217 standard) this string is capitalized
    #                              (ie, 'UNITED STATES')
    # @attr_reader [String] currency A colloquial name for this currency (ie. "US Dollar")
    # @attr_reader [String] alphabetic_code The shorthand, three digit letter code for this currency (ie 'USD')
    # @attr_reader [Integer] numeric_code The ISO 4217 code for this currency 840
    # @attr_reader [Integer] minor_unit The default precision for this currency, as would be typically implied.
    #                                   For the case of USD, this would be 2. Indicating two decimal digits for a
    #                                   default transcription of a USD amount.
    # @attr_reader [String] symbol The shorthand, (typically) one character symbol code for this currency (ie '$')
    class Currency
      # Raised on a parse error
      class Error < StandardError; end

      attr_reader :entity, :currency, :alphabetic_code, :numeric_code, :minor_unit, :symbol

      # Create a Currency commodity, from constituent parts
      # @param [Hash] opts The parts of this complex commodity
      # @option opts [String] entity see {Currency#entity}
      # @option opts [String] currency see {Currency#currency}
      # @option opts [String] alphabetic_code see {Currency#alphabetic_code}
      # @option opts [Integer] numeric_code see {Currency#numeric_code}
      # @option opts [Integer] minor_unit see {Currency#minor_unit}
      # @option opts [String] symbol see {Currency#symbol}
      def initialize(opts = {})
        @entity = opts[:entity]
        @currency = opts[:currency]
        @alphabetic_code = opts[:alphabetic_code]
        @numeric_code = opts[:numeric_code].to_i
        @minor_unit = opts[:minor_unit].to_i
        @symbol = opts[:symbol]
        raise Error, format('Unabled to parse config entry: "%s"', inspect) unless valid?
      end

      # Indicates whether or not this instance contains all required fields
      # @return [TrueClass,FalseClass] whether or not we're valid
      def valid?
        [entity, currency, alphabetic_code, numeric_code, minor_unit].all?
      end

      # Create a new commodity, from this currency, with the provided quantity
      # @param [Integer] quantity The quantity component, of the newly created commodity
      # @return [RRA::Journal::Commodity]
      def to_commodity(quantity)
        RRA::Journal::Commodity.new symbol || alphabetic_code, alphabetic_code, quantity, minor_unit
      end

      # Load and return a parsed RRA::Journal::Currency, out of the provided
      # {https://github.com/brighton36/rra/blob/main/resources/iso-4217-currencies.json iso-4217-currencies.json}
      # file.
      # @param [String] str Either a three digit :alphabetic_code, or a single digit :symbol
      # @return [RRA::Journal::Currency] the requested currency, with its default parameters
      def self.from_code_or_symbol(str)
        @currencies ||= begin
          unless currencies_config && File.readable?(currencies_config)
            raise StandardError, 'Missing currency config file'
          end

          JSON.parse(File.read(currencies_config)).map do |c|
            new(c.transform_keys { |k| k.downcase.tr(' ', '_').to_sym })
          end
        end
        @currencies.find { |c| (c.alphabetic_code && c.alphabetic_code == str) || (c.symbol && c.symbol == str) }
      end

      class << self
        attr_accessor :currencies_config
      end
    end
  end
end
