# frozen_string_literal: true

require 'shellwords'
require 'json'

require_relative '../journal/pricer'
require_relative '../pta'

module RRA
  class Pta
    # A plain text accounting adapter implementation, for the 'ledger' pta command.
    # This class conforms the ledger query, and output, interfaces in a ruby-like
    # syntax, and with structured ruby objects as outputs.
    #
    # For a more detailed example of these queries in action, take a look at the
    # {https://github.com/brighton36/rra/blob/main/test/test_pta_adapter.rb test/test_pta_adapter.rb}
    class HLedger < RRA::Pta
      # @!visibility private
      BIN_PATH = '/usr/bin/hledger'

      module Output
        # The base class from which RRA::Pta::HLedger's specific json-based outputs inherit.
        class JsonBase
          attr_reader :json, :pricer

          def initialize(json, options)
            @pricer = options[:pricer] || RRA::Journal::Pricer.new
            @json = JSON.parse json, symbolize_names: true
          end

          private

          def commodity_from_json(json)
            symbol = json[:acommodity]
            raise RRA::Pta::AssertionError unless json.key? :aquantity

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

            raise RRA::Pta::AssertionError unless @json.length == 2

            @accounts = @json[0].collect do |json_account|
              # I'm not sure why there are two identical entries here, for fullname
              raise RRA::Pta::AssertionError unless json_account[0] == json_account[1]

              RRA::Pta::BalanceAccount.new(json_account[0],
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

              RRA::Pta::RegisterTransaction.new(
                date,
                postings[0][2], # Payee
                (postings.map do |posting|
                  amounts, totals = [posting[3][:pamount], posting[4]].map do |pamounts|
                    pamounts.map { |pamount| commodity_from_json pamount }
                  end

                  RRA::Pta::RegisterPosting.new(
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

      # Return the tags that were found, given the specified journal path, and filters.
      #
      # The behavior between hledger and ledger are rather different here. Ledger has a slightly different
      # featureset than HLedger, regarding tags. As such, while the return format is the same between implementations.
      # The results for a given query won't be identical between pta implementations. Mostly, these results differ
      # when a \\{values: true} option is supplied. In that case, ledger will return tags in a series of keys and
      # values, separated by a colon, one per line. hledger, in that case, will only return the tag values themselves,
      # without denotating their key.
      #
      # This method will simply parse the output of hledger, and return that.
      # @param [Array<Object>] args Arguments and options, passed to the pta command. See {RRA::Pta#args_and_opts} for
      #                             details
      # @return [Array<String>] An array of the lines returned by hledger, split into strings. In most cases, this
      #                         could also be described as simply 'an array of the filtered tags'.
      def tags(*args)
        args, opts = args_and_opts(*args)
        command('tags', *args, opts).split("\n")
      end

      # Return the files that were encountered, when parsing the provided arguments.
      # The output of this method should be identical, regardless of the Pta Adapter that resolves the request.
      #
      # @param [Array<Object>] args Arguments and options, passed to the pta command. See {RRA::Pta#args_and_opts} for
      #                             details
      # @return [Array<String>] An array of paths that were referenced when fetching data in provided arguments.
      def files(*args)
        args, opts = args_and_opts(*args)
        # TODO: This should get its own error class...
        raise StandardError, "Unexpected argument(s) : #{args.inspect}" unless args.empty?

        command('files', opts).split("\n")
      end

      # Returns the newest transaction, retured in set of transactions filtered with the provided arguments.
      # This method is mostly a wrapper around {#register}, which a return of the .last element in its set.
      # The only reason this method here is to ensure parity with the {RRA::Pta::Ledger} class, which, exists
      # because an accelerated query is offered by that pta implementation. This method may produce
      # counterintutive results, if you override the sort: option.
      #
      # NOTE: For almost any case you think you want to use this method, {#newest_transaction_date} is probably
      # what you want, as that function has an accelerated implementation provided by hledger.
      #
      # @param [Array<Object>] args Arguments and options, passed to the pta command. See {RRA::Pta#args_and_opts} for
      #                             details.
      # @return [RRA::Pta::RegisterTransaction] The newest transaction in the set
      def newest_transaction(*args)
        register(*args)&.transactions&.last
      end

      # Returns the oldest transaction, retured in set of transactions filtered with the provided arguments.
      # This method is mostly a wrapper around {RRA::Pta::HLedger#register}, which a return of the .last element in its
      # set. The only reason this method here is to ensure parity with the {RRA::Pta::Ledger} class, which, exists
      # because an accelerated query is offered by that pta implementation. This method may produce
      # counterintutive results, if you override the sort: option.
      #
      # NOTE: There is almost certainly, no a good reason to be using this method. Perhaps in the future,
      # hledger will offer an equivalent to ledger's --head and --tail options, at which time this method would
      # make sense.
      #
      # @param [Array<Object>] args Arguments and options, passed to the pta command. See {RRA::Pta#args_and_opts} for
      #                             details.
      # @return [RRA::Pta::RegisterTransaction] The oldest transaction in the set
      def oldest_transaction(*args)
        register(*args)&.transactions&.first
      end

      # Returns the value of the 'Last transaction' key, of the #{RRA::Pta#stats} method. This method is a fast query to
      # resolve.
      # @param [Array<Object>] args Arguments and options, passed to the pta command. See {RRA::Pta#args_and_opts} for
      #                             details.
      # @return [Date] The date of the newest transaction found in your files.
      def newest_transaction_date(*args)
        Date.strptime stats(*args)['Last transaction'], '%Y-%m-%d'
      end

      # Run the 'hledger balance' command, and return it's output.
      # @param [Array<Object>] args Arguments and options, passed to the pta command. See {RRA::Pta#args_and_opts} for
      #                             details.
      # @return [RRA::Pta::HLedger::Output::Balance] A parsed, hierarchial, representation of the output
      def balance(*args)
        args, opts = args_and_opts(*args)
        RRA::Pta::HLedger::Output::Balance.new command('balance', *args, { 'output-format': 'json' }.merge(opts))
      end

      # Run the 'hledger register' command, and return it's output.
      # @param [Array<Object>] args Arguments and options, passed to the pta command. See {RRA::Pta#args_and_opts} for
      #                             details.
      # @return [RRA::Pta::HLedger::Output::Register] A parsed, hierarchial, representation of the output
      def register(*args)
        args, opts = args_and_opts(*args)

        pricer = opts.delete :pricer
        # TODO: Do we really need this? probably..
        # translate_meta_accounts = opts[:empty]

        # TODO: Provide translate_meta_accounts: translate_meta_accounts here (?)
        RRA::Pta::HLedger::Output::Register.new command('register', *args, { 'output-format': 'json' }.merge(opts)),
                                                monthly: (opts[:monthly] == true),
                                                pricer: pricer
      end
    end
  end
end
