require 'shellwords'
require 'json'

require_relative '../pricer'

module RRA::HLedger
  HLEDGER='/usr/bin/hledger'

  # TODO: We could probably DRY this against the ledger implementation
  class AssertionError < StandardError
  end
  
  module Output
    class Balance
      # TODO: DRY Out the Readerbase into another module...
      class Account < RRA::Ledger::Output::ReaderBase
        readers :fullname, :amounts
      end
      
      attr_reader :accounts, :summary_amounts

      def initialize(json, options = {})
        @pricer = options[:pricer] || RRA::Pricer.new
        @json = JSON.load json, symbolize_names: true

        # This first implementation was written against:
        #   hledger bal -O json Personal:Assets:Cash --end 2021-09-01
        raise AssertionError unless @json.length == 2

        @accounts = @json[0].collect{|json_account|
          # I'm not sure why there are two identical entries here, for fullname
          raise AssertionError unless json_account[0] == json_account[1]

          Account.new json_account[0], 
            json_account[3].collect{|l| commodity_from_json l } 
        }

        @summary_amounts = @json[1].collect{|json_amount| 
          commodity_from_json json_amount }
      end

      private

      def commodity_from_json(json)
        symbol = json['acommodity']
        raise AssertionError unless json.has_key? 'aquantity'

        currency = RRA::Journal::Currency.from_code_or_symbol symbol
        # TODO: It seems like HLedger defaults to 10 digits. Probably
        # we should shrink these numbers down to the currency specifier...
        RRA::Journal::Commodity.new symbol, 
          (currency) ? currency.alphabetic_code : symbol,
          json['aquantity']['decimalMantissa'], 
          json['aquantity']['decimalPlaces']
      end

    end
  end

  # hledger bal -O json Personal:Assets:Cash --end 2021-09-01
  def self.balance(account, opts = {})
    RRA::HLedger::Output::Balance.new command(*opts_to_args(opts)+[
      "balance", "--output-format", "json", account])
  end

  # TODO: We could probably DRY this against the ledger implementation. 
  def self.command(*args)
    cmd = ([HLEDGER]+args.collect{|a| Shellwords.escape a}).join(' ')
    IO.popen(cmd).read
  end

  private

  # TODO: We could probably DRY this against the ledger implementation. 
  # TODO: Similarly, we should support the from_s syntax
  def self.opts_to_args(opts)
    opts.collect{|k, v| ['--%s' % [k.to_s], (v == true) ? nil : v] }.flatten.compact
  end
end
