# frozen_string_literal: true

require 'json'

module RRA
  class Journal
    # This abstraction provides for the basic properties of currency, and the
    # loading of default currencies from a yaml file included in the package.
    # This class is used in several places throughout the codebase, and provides
    # a standard set of interfaces for working with this global repository of
    # currency properties.
    class Currency
      class Error < StandardError; end

      attr_reader :entity, :currency, :alphabetic_code, :numeric_code, :minor_unit, :symbol

      def initialize(from_json)
        @entity = from_json['Entity']
        @currency = from_json['Currency']
        @alphabetic_code = from_json['Alphabetic Code']
        @numeric_code = from_json['Numeric Code'].to_i
        @minor_unit = from_json['Minor unit'].to_i
        @symbol = from_json['Symbol']
        raise Error, format('Unabled to parse config entry: "%s"', inspect) unless valid?
      end

      def valid?
        [entity, currency, alphabetic_code, numeric_code, minor_unit].all?
      end

      def to_commodity(quantity)
        RRA::Journal::Commodity.new symbol || alphabetic_code, alphabetic_code, quantity, minor_unit
      end

      def self.from_code_or_symbol(str)
        @currencies ||= begin
          unless currencies_config && File.readable?(currencies_config)
            raise StandardError, 'Missing currency config file'
          end

          JSON.parse(File.read(currencies_config)).collect { |c| new c }
        end
        @currencies.find { |c| (c.alphabetic_code && c.alphabetic_code == str) || (c.symbol && c.symbol == str) }
      end

      class << self
        attr_accessor :currencies_config
      end
    end
  end
end
