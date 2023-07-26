# frozen_string_literal: true

require 'shellwords'
require 'json'

require_relative '../pricer'
require_relative '../pta_connection'

class RRA::HLedger < RRA::PTAConnection
  BIN_PATH = '/usr/bin/hledger'

  module Output
    class JsonBase
      attr_reader :json, :pricer

      def initialize(json, options)
        @pricer = options[:pricer] || RRA::Pricer.new

        # TODO: Figure out why .parse breaks the spec...
        @json = JSON.load json, symbolize_names: true
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

    class Balance < JsonBase
      attr_reader :accounts, :summary_amounts

      def initialize(json, options = {})
        super json, options

        raise RRA::PTAConnection::AssertionError unless @json.length == 2

        @accounts = @json[0].collect do |json_account|
          # I'm not sure why there are two identical entries here, for fullname
          raise RRA::PTAConnection::AssertionError unless json_account[0] == json_account[1]

          RRA::PTAConnection::BalanceAccount.new(json_account[0],
                      json_account[3].collect { |l| commodity_from_json l })
        end

        @summary_amounts = @json[1].collect { |json_amount| commodity_from_json json_amount }
      end
    end

    class Register < JsonBase
      attr_reader :transactions

      # TODO: I think we need to integrate the ignore_unknown_codes... but, write test on that.
      # Because I'm not sure what it does...
      def initialize(json, options = {})
        super json, options

        @transactions = @json.each_with_object([]) do |row, sum|
          row[0] ? (sum << [row]) : (sum.last << row)
        end

        @transactions.map! do |postings|
          date = Date.strptime(postings[0][0], '%Y-%m-%d')

          RRA::PTAConnection::RegisterTransaction.new(
            date,
            postings[0][2], # Payee
            (postings.map do |posting|
               amounts, totals = [posting[3]['pamount'], posting[4]].map do |pamounts|
                 pamounts.map { |pamount| commodity_from_json pamount }
               end

               RRA::PTAConnection::RegisterPosting.new(
                 posting[3]['paccount'],
                 amounts,
                 totals,
                 posting[3]['ptags'].to_h do |pair|
                   [pair.first, pair.last.empty? ? true : pair.last]
                 end,
                 pricer: pricer,
                 # This sets our date to the end -of the month, if this is a
                 # monthly query
                 price_date: options[:monthly] ? Date.new(date.year, date.month, -1) : date
               )
             end)
          )
        end
      end
    end
  end

  def self.files(opts = {})
    command('files', opts).split("\n")
  end

  def self.balance(account, opts = {})
    RRA::HLedger::Output::Balance.new command 'balance', account, { 'output-format': 'json' }.merge(opts)
  end

  def self.register(*args)
    opts = args.last.is_a?(Hash) ? args.pop : {}

    pricer = opts.delete :pricer
    #TODO: Do we really need this? probably..
    # translate_meta_accounts = opts[:empty]

    RRA::HLedger::Output::Register.new command('register', *args, { 'output-format': 'json' }.merge(opts)),
                                       monthly: (opts[:monthly] == true),
                                       pricer: pricer
                                       # TODO?
                                       # translate_meta_accounts: translate_meta_accounts
  end
end
