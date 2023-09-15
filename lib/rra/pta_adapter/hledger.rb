# frozen_string_literal: true

require 'shellwords'
require 'json'

require_relative '../pricer'
require_relative '../pta_adapter'

module RRA
  # A plain text accounting adapter implementatin, for the 'hledger' pta command.
  # This class conforms the query and output interfaces to ledger, in a more ruby-like
  # syntax.
  class HLedger < RRA::PtaAdapter
    BIN_PATH = '/usr/bin/hledger'

    module Output
      # The base class from which RRA::HLedger's specific json-based outputs inherit.
      class JsonBase
        attr_reader :json, :pricer

        def initialize(json, options)
          @pricer = options[:pricer] || RRA::Pricer.new
          @json = JSON.parse json, symbolize_names: true
        end

        private

        def commodity_from_json(json)
          symbol = json[:acommodity]
          raise RRA::PtaAdapter::AssertionError unless json.key? :aquantity

          currency = RRA::Journal::Currency.from_code_or_symbol symbol
          # TODO: It seems like HLedger defaults to 10 digits. Probably
          # we should shrink these numbers down to the currency specifier...
          RRA::Journal::Commodity.new symbol,
                                      currency ? currency.alphabetic_code : symbol,
                                      json[:aquantity][:decimalMantissa],
                                      json[:aquantity][:decimalPlaces]
        end
      end

      # An json output parsing implementation for balance queries to ledger
      class Balance < JsonBase
        attr_reader :accounts, :summary_amounts

        def initialize(json, options = {})
          super json, options

          raise RRA::PtaAdapter::AssertionError unless @json.length == 2

          @accounts = @json[0].collect do |json_account|
            # I'm not sure why there are two identical entries here, for fullname
            raise RRA::PtaAdapter::AssertionError unless json_account[0] == json_account[1]

            RRA::PtaAdapter::BalanceAccount.new(json_account[0],
                                                json_account[3].collect { |l| commodity_from_json l })
          end

          @summary_amounts = @json[1].collect { |json_amount| commodity_from_json json_amount }
        end
      end

      # An json output parsing implementation for register queries to ledger
      class Register < JsonBase
        attr_reader :transactions

        def initialize(json, options = {})
          super json, options

          @transactions = @json.each_with_object([]) do |row, sum|
            row[0] ? (sum << [row]) : (sum.last << row)
          end

          @transactions.map! do |postings|
            date = Date.strptime postings[0][0], '%Y-%m-%d'

            RRA::PtaAdapter::RegisterTransaction.new(
              date,
              postings[0][2], # Payee
              (postings.map do |posting|
                amounts, totals = [posting[3][:pamount], posting[4]].map do |pamounts|
                  pamounts.map { |pamount| commodity_from_json pamount }
                end

                RRA::PtaAdapter::RegisterPosting.new(
                  posting[3][:paccount],
                  amounts,
                  totals,
                  posting[3][:ptags].to_h do |pair|
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

    def tags(*args)
      args, opts = args_and_opts(*args)
      command('tags', *args, opts).split("\n")
    end

    def files(*args)
      args, opts = args_and_opts(*args)
      # TODO: This should get its own error class...
      raise StandardError, "Unexpected argument(s) : #{args.inspect}" unless args.empty?

      command('files', opts).split("\n")
    end

    # This is a really inefficient function. Probably you shouldn't use it. It's mostly here
    # to ensure compatibility with the ledger adapter. Consider using #newest_transaction_date
    # instead
    def newest_transaction(*args)
      register(*args)&.transactions&.last
    end

    # This is a really inefficient function. Probably you shouldn't use it. It's mostly here
    # to ensure compatibility with the ledger adapter.
    def oldest_transaction(*args)
      register(*args)&.transactions&.first
    end

    # This optimization exists, mostly due to the lack of a .last or .first in hledger.
    # And, the utility of this specific function, in the RRA.config.
    def newest_transaction_date(*args)
      Date.strptime stats(*args)['Last transaction'], '%Y-%m-%d'
    end

    def balance(*args)
      args, opts = args_and_opts(*args)
      RRA::HLedger::Output::Balance.new command('balance', *args, { 'output-format': 'json' }.merge(opts))
    end

    def register(*args)
      args, opts = args_and_opts(*args)

      pricer = opts.delete :pricer
      # TODO: Do we really need this? probably..
      # translate_meta_accounts = opts[:empty]

      # TODO: Provide translate_meta_accounts: translate_meta_accounts here (?)
      RRA::HLedger::Output::Register.new command('register', *args, { 'output-format': 'json' }.merge(opts)),
                                         monthly: (opts[:monthly] == true),
                                         pricer: pricer
    end
  end
end
