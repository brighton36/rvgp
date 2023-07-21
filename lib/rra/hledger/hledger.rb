# frozen_string_literal: true

require 'shellwords'
require 'json'

require_relative '../pricer'
require_relative '../pta_connection'

class RRA::HLedger < RRA::PTAConnection
  BIN_PATH = '/usr/bin/hledger'

  module Output
    class Balance
      # TODO: DRY Out the Readerbase into another module...
      class Account < RRA::Ledger::Output::ReaderBase
        readers :fullname, :amounts
      end

      attr_reader :accounts, :summary_amounts

      def initialize(json, options = {})
        @pricer = options[:pricer] || RRA::Pricer.new

        # TODO: Figure out why .parse breaks the spec...
        @json = JSON.load json, symbolize_names: true

        raise RRA::PTAConnection::AssertionError unless @json.length == 2

        @accounts = @json[0].collect do |json_account|
          # I'm not sure why there are two identical entries here, for fullname
          raise RRA::PTAConnection::AssertionError unless json_account[0] == json_account[1]

          Account.new(json_account[0],
                      json_account[3].collect { |l| commodity_from_json l })
        end

        @summary_amounts = @json[1].collect { |json_amount| commodity_from_json json_amount }
      end

      private

      def commodity_from_json(json)
        symbol = json['acommodity']
        raise RRA::PTAConnection::AssertionError unless json.key? 'aquantity'

        currency = RRA::Journal::Currency.from_code_or_symbol symbol
        # TODO: It seems like HLedger defaults to 10 digits. Probably
        # we should shrink these numbers down to the currency specifier...
        RRA::Journal::Commodity.new symbol,
                                    currency ? currency.alphabetic_code : symbol,
                                    json['aquantity']['decimalMantissa'],
                                    json['aquantity']['decimalPlaces']
      end
    end
  end

  def self.files(opts = {})
    command('files', opts).split("\n")
  end

  def self.balance(account, opts = {})
    RRA::HLedger::Output::Balance.new command('balance', '--output-format', 'json', account, opts)
  end
end
