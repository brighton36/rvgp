require 'json'

class RRA::Journal::Currency
  class Error < StandardError; end

  attr_reader :entity, :currency, :alphabetic_code, :numeric_code, :minor_unit,
    :symbol
  
  def initialize(from_json)
    @entity = from_json["Entity"]
    @currency = from_json["Currency"]
    @alphabetic_code = from_json["Alphabetic Code"]
    @numeric_code = from_json["Numeric Code"].to_i
    @minor_unit = from_json["Minor unit"].to_i
    @symbol = from_json["Symbol"]
    raise Error, "Unabled to parse config entry: \"%s\"" % self.inspect unless valid?
  end

  def valid?
    [entity, currency, alphabetic_code, numeric_code, minor_unit].all?
  end

  def to_commodity(quantity)
    RRA::Journal::Commodity.new symbol || alphabetic_code, alphabetic_code, quantity, 
      minor_unit
  end

  def self.from_code_or_symbol(s)
    @currencies ||= begin
      raise StandardError, "Missing currency config file" unless (
        self.currencies_config and File.readable? self.currencies_config )
      JSON.load(File.open(self.currencies_config)).collect{|c| self.new c}
    end
    @currencies.find{|c| c.alphabetic_code == s or c.symbol == s }
  end

  def self.currencies_config=(str)
    @currencies_config = str
  end

  def self.currencies_config
    @currencies_config
  end
end

