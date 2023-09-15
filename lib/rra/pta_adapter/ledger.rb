# frozen_string_literal: true

require 'shellwords'
require 'open3'
require 'nokogiri'

require_relative '../pta_adapter'
require_relative '../pricer'

module RRA
  # A plain text accounting adapter implementatin, for the 'ledger' pta command.
  # This class conforms the query and output interfaces to ledger, in a more ruby-like
  # syntax.
  class Ledger < RRA::PtaAdapter
    BIN_PATH = '/usr/bin/ledger'

    module Output
      # The base class from which RRA::Ledger's specific xml-based outputs inherit.
      class XmlBase
        # A commodity, as reported in the ledger xml meta-output
        class Commodity < RRA::PtaAdapter::ReaderBase
          readers :symbol, :date, :price
        end

        attr_reader :doc, :commodities, :pricer, :options

        def initialize(xml, options)
          @doc = Nokogiri::XML xml, &:noblanks
          @pricer = options[:pricer] || RRA::Pricer.new

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

              RRA::PtaAdapter::BalanceAccount.new(
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

            RRA::PtaAdapter::RegisterTransaction.new(
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

                RRA::PtaAdapter::RegisterPosting.new(
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

    def balance(*args)
      args, opts = args_and_opts(*args)

      RRA::Ledger::Output::Balance.new command('xml', *args, opts)
    end

    # The behavior between hledger and ledger are rather different here. This behavior
    # strikes a balance between compatibility and features. The latter of which, ledger
    # seems to excel at.
    def tags(*args)
      args, opts = args_and_opts(*args)

      # The first arg, is the tag whose values we want. This is how hledger does it, and
      # we just copy that
      for_tag = args.shift unless args.empty?

      tags = command('tags', *args, opts).split("\n")

      for_tag ? tags.map { |tag| ::Regexp.last_match(1) if /\A#{for_tag}: *(.*)/.match tag }.compact : tags
    end

    def register(*args)
      args, opts = args_and_opts(*args)

      pricer = opts.delete :pricer
      translate_meta_accounts = opts[:empty]

      # We stipulate, by default, a date sort. Mostly because it makes sense. But, also so
      # that this matches HLedger's default sort order
      RRA::Ledger::Output::Register.new command('xml', *args, { sort: 'date' }.merge(opts)),
                                        monthly: (opts[:monthly] == true),
                                        empty: opts[:empty],
                                        pricer: pricer,
                                        translate_meta_accounts: translate_meta_accounts
    end

    def files(*args)
      args, opts = args_and_opts(*args)

      # TODO: This should get its own error class...
      raise StandardError, "Unexpected argument(s) : #{args.inspect}" unless args.empty?

      stats(*args, opts)['Files these postings came from'].tap do |ret|
        ret.unshift opts[:file] if opts.key?(:file) && !ret.include?(opts[:file])
      end
    end

    def newest_transaction(*args)
      args, opts = args_and_opts(*args)
      first_transaction(*args, opts.merge(sort: 'date', tail: 1))
    end

    def oldest_transaction(*args)
      args, opts = args_and_opts(*args)
      first_transaction(*args, opts.merge(sort: 'date', head: 1))
    end

    def newest_transaction_date(*args)
      Date.strptime ::Regexp.last_match(1), '%y-%b-%d' if /to ([^ ]+)/.match stats(*args)['Time period']
    end

    def first_transaction(*args)
      reg = register(*args)

      raise RRA::PtaAdapter::AssertionError, 'Expected a single transaction' unless reg.transactions.length == 1

      reg.transactions.first
    end
  end
end
