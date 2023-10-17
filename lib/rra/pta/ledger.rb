# frozen_string_literal: true

require 'shellwords'
require 'open3'
require 'nokogiri'

require_relative '../pta'
require_relative '../journal/pricer'

module RRA
  class Pta
    # A plain text accounting adapter implementation, for the 'ledger' pta command.
    # This class conforms the ledger query, and output, interfaces in a ruby-like
    # syntax, and with structured ruby objects as outputs.
    #
    # For a more detailed example of these queries in action, take a look at the
    # {https://github.com/brighton36/rra/blob/main/test/test_pta_adapter.rb test/test_pta_adapter.rb}
    class Ledger < RRA::Pta
      # @!visibility private
      BIN_PATH = '/usr/bin/ledger'

      module Output
        # The base class from which RRA::Pta::Ledger's specific xml-based outputs inherit.
        class XmlBase
          # A commodity, as reported in the ledger xml meta-output
          class Commodity < RRA::Base::Reader
            readers :symbol, :date, :price
          end

          attr_reader :doc, :commodities, :pricer, :options

          def initialize(xml, options)
            @doc = Nokogiri::XML xml, &:noblanks
            @pricer = options[:pricer] || RRA::Journal::Pricer.new

            @commodities = doc.search('//commodities//commodity[annotation]').collect do |xcommodity|
              next unless ['symbol', 'date', 'price', 'price/commodity/symbol',
                           'price/quantity'].all? { |path| xcommodity.at(path) }

              symbol = xcommodity.at('symbol').content
              date = Date.strptime(xcommodity.at('date').content, '%Y/%m/%d')
              commodity = RRA::Journal::Commodity.from_symbol_and_amount(
                xcommodity.at('price/commodity/symbol').content,
                xcommodity.at('price/quantity').content
              )

              @pricer.add date.to_time, symbol, commodity
              Commodity.new symbol, date, commodity
            end
          end
        end

        # An Xml output parsing implementation for balance queries to ledger
        class Balance < XmlBase
          attr_reader :accounts

          def initialize(xml, options = {})
            super xml, options

            # NOTE: Our output matches the --flat output, of ledger. We mostly do this
            # because hledger defaults to the same output. It might cause some
            # expectations to fail though, if you're comparing our balance return,
            # to the cli output of balance
            #
            # Bear in mind that this query is slightly odd, in that account is nested
            # So, I stipulate that we are at the end of a nest "not account" and
            # have children "*"
            xaccounts = doc.xpath('//accounts//account[not(account[*]) and *]')

            if xaccounts
              @accounts = xaccounts.collect do |xaccount|
                fullname = xaccount.at('fullname')&.content

                next unless fullname

                RRA::Pta::BalanceAccount.new(
                  fullname,
                  xaccount.xpath('account-amount/amount|account-amount/*/amount').collect do |amount|
                    commodity = RRA::Journal::Commodity.from_symbol_and_amount(
                      amount.at('symbol').content, amount.at('quantity').content
                    )
                    commodity if commodity.quantity != 0
                  end.compact
                )
              end.compact
            end
          end
        end

        # An Xml output parsing implementation for register queries to ledger
        class Register < XmlBase
          attr_reader :transactions

          def initialize(xml, options = {})
            super xml, options

            @transactions = doc.xpath('//transactions/transaction').collect do |xt|
              date = Date.strptime(xt.at('date').content, '%Y/%m/%d')

              RRA::Pta::RegisterTransaction.new(
                date,
                xt.at('payee').content,
                xt.xpath('postings/posting').collect do |xp|
                  amounts, totals = *%w[post-amount total].collect do |attr|
                    xp.at(attr).search('amount').collect do |xa|
                      RRA::Journal::Commodity.from_symbol_and_amount(
                        xa.at('commodity/symbol')&.content,
                        xa.at('quantity').content
                      )
                    end
                  end

                  if options[:empty] == false
                    amounts.reject! { |amnt| amnt.quantity.zero? }
                    totals.reject! { |amnt| amnt.quantity.zero? }

                    next if [amounts, totals].all?(&:empty?)
                  end

                  account = xp.at('account/name').content

                  # This phenomenon of '<None>' and '<total>', seems to only happen
                  # when the :empty parameter is passed.
                  if options[:translate_meta_accounts]
                    case account
                    when '<None>' then account = nil
                    when '<Total>' then account = :total
                    end
                  end

                  RRA::Pta::RegisterPosting.new(
                    account,
                    amounts,
                    totals,
                    xp.search('metadata/value').to_h { |xvalue| [xvalue['key'], xvalue.content] },
                    pricer: pricer,
                    # This sets our date to the end -of the month, if this is a
                    # monthly query
                    price_date: options[:monthly] ? Date.new(date.year, date.month, -1) : date
                  )
                end.compact
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
      # This method will simply parse the output of ledger, and return that.
      # @param [Array<Object>] args Arguments and options, passed to the pta command. See {RRA::Pta#args_and_opts} for
      #                             details
      # @return [Array<String>] An array of the lines returned by ledger, split into strings. In most cases, this
      #                         could also be described as simply 'an array of the filtered tags'.
      def tags(*args)
        args, opts = args_and_opts(*args)

        # The first arg, is the tag whose values we want. This is how hledger does it, and
        # we just copy that
        for_tag = args.shift unless args.empty?

        tags = command('tags', *args, opts).split("\n")

        for_tag ? tags.map { |tag| ::Regexp.last_match(1) if /\A#{for_tag}: *(.*)/.match tag }.compact : tags
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

        stats(*args, opts)['Files these postings came from'].tap do |ret|
          ret.unshift opts[:file] if opts.key?(:file) && !ret.include?(opts[:file])
        end
      end

      # Returns the newest transaction, retured in set of transactions filtered with the provided arguments.
      # This method is mostly a wrapper around \\{#register} with the \\{tail: 1} option passed to that method. This
      # method may produce counterintutive results, if you override the sort: option.
      #
      # NOTE: For almost any case you think you want to use this method, {#newest_transaction_date} is probably
      # more efficient. Particularly since this method has accelerated implementation in its {RRA::Pta::Hledger}
      # counterpart
      #
      # @param [Array<Object>] args Arguments and options, passed to the pta command. See {RRA::Pta#args_and_opts} for
      #                             details.
      # @return [RRA::Pta::RegisterTransaction] The newest transaction in the set
      def newest_transaction(*args)
        args, opts = args_and_opts(*args)
        first_transaction(*args, opts.merge(sort: 'date', tail: 1))
      end

      # Returns the oldest transaction, retured in set of transactions filtered with the provided arguments.
      # This method is mostly a wrapper around {RRA::Pta::Ledger#register} with the \\{head: 1} option passed to that
      # method. This method may produce counterintutive results, if you override the sort: option.
      #
      # @param [Array<Object>] args Arguments and options, passed to the pta command. See {RRA::Pta#args_and_opts} for
      #                             details.
      # @return [RRA::Pta::RegisterTransaction] The oldest transaction in the set
      def oldest_transaction(*args)
        args, opts = args_and_opts(*args)
        first_transaction(*args, opts.merge(sort: 'date', head: 1))
      end

      # Returns the value of the 'Time Period' key, of the #{RRA::Pta#stats} method. This method is a fast query to
      # resolve.
      # @param [Array<Object>] args Arguments and options, passed to the pta command. See {RRA::Pta#args_and_opts} for
      #                             details.
      # @return [Date] The date of the newest transaction found in your files.
      def newest_transaction_date(*args)
        Date.strptime ::Regexp.last_match(1), '%y-%b-%d' if /to ([^ ]+)/.match stats(*args)['Time period']
      end

      # Run the 'ledger balance' command, and return it's output.
      # @param [Array<Object>] args Arguments and options, passed to the pta command. See {RRA::Pta#args_and_opts} for
      #                             details.
      # @return [RRA::Pta::Ledger::Output::Balance] A parsed, hierarchial, representation of the output
      def balance(*args)
        args, opts = args_and_opts(*args)

        RRA::Pta::Ledger::Output::Balance.new command('xml', *args, opts)
      end

      # Run the 'ledger register' command, and return it's output.
      # @param [Array<Object>] args Arguments and options, passed to the pta command. See {RRA::Pta#args_and_opts} for
      #                             details.
      # @return [RRA::Pta::Ledger::Output::Register] A parsed, hierarchial, representation of the output
      def register(*args)
        args, opts = args_and_opts(*args)

        pricer = opts.delete :pricer
        translate_meta_accounts = opts[:empty]

        # We stipulate, by default, a date sort. Mostly because it makes sense. But, also so
        # that this matches HLedger's default sort order
        RRA::Pta::Ledger::Output::Register.new command('xml', *args, { sort: 'date' }.merge(opts)),
                                               monthly: (opts[:monthly] == true),
                                               empty: opts[:empty],
                                               pricer: pricer,
                                               translate_meta_accounts: translate_meta_accounts
      end

      private

      def first_transaction(*args)
        reg = register(*args)

        raise RRA::Pta::AssertionError, 'Expected a single transaction' unless reg.transactions.length == 1

        reg.transactions.first
      end
    end
  end
end
