# frozen_string_literal: true

require 'shellwords'
require 'open3'
require 'nokogiri'

require_relative '../pta_connection'
require_relative '../pricer'

class RRA::Ledger < RRA::PTAConnection
  BIN_PATH = '/usr/bin/ledger'

  module Output
    class XmlBase
      class Commodity < RRA::PTAConnection::ReaderBase
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

    class Balance < XmlBase
      attr_reader :accounts

      def initialize(needle, xml, options = {})
        super xml, options

        # Bear in mind that this query is slightly odd, in that account is nested
        # So, I stipulate that we are at the end of a nest "not account" and
        # have children "*"
        xaccounts = doc.xpath('//accounts//account[not(account) and *]')

        if xaccounts
          @accounts = xaccounts.collect do |xaccount|
            account = RRA::PTAConnection::BalanceAccount.new(
              xaccount.at('fullname').content,
              xaccount.xpath('account-amount/amount|account-amount/*/amount').collect do |amount|
                commodity = RRA::Journal::Commodity.from_symbol_and_amount(
                  amount.at('symbol').content, amount.at('quantity').content
                )
                commodity if commodity.quantity != 0
              end.compact
            )
            account if [/#{Regexp.escape(needle)}/.match(account.fullname), !account.amounts.empty?].all?
          end.compact
        end
      end
    end

    class Register < XmlBase
      attr_reader :transactions

      def initialize(xml, options = {})
        super xml, options

        @transactions = doc.xpath('//transactions/transaction').collect do |xt|
          date = Date.strptime(xt.at('date').content, '%Y/%m/%d')

          RRA::PTAConnection::RegisterTransaction.new(
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

              account = xp.at('account/name').content

              # This phenomenon of '<None>' and '<total>', seems to only happen
              # when the :empty parameter is passed.
              if options[:translate_meta_accounts]
                case account
                when '<None>' then account = nil
                when '<Total>' then account = :total
                end
              end

              RRA::PTAConnection::RegisterPosting.new(
                account,
                amounts,
                totals,
                xp.search('metadata/value').to_h { |xvalue| [xvalue['key'], xvalue.content] },
                pricer: pricer,
                # This sets our date to the end -of the month, if this is a
                # monthly query
                price_date: options[:monthly] ? Date.new(date.year, date.month, -1) : date
              )
            end
          )
        end
      end
    end
  end

  def balance(account, opts = {})
    RRA::Ledger::Output::Balance.new account, command('xml', opts)
  end

  def register(*args)
    opts = args.last.is_a?(Hash) ? args.pop : {}

    pricer = opts.delete :pricer
    translate_meta_accounts = opts[:empty]

    # We stipulate, by default, a date sort. Mostly because it makes sense. But, also so
    # that this matches HLedger's default sort order
    RRA::Ledger::Output::Register.new command('xml', *args, { sort: 'date' }.merge(opts)),
                                      monthly: (opts[:monthly] == true),
                                      pricer: pricer,
                                      translate_meta_accounts: translate_meta_accounts
  end

  def newest_transaction(account = nil, opts = {})
    first_transaction account, opts.merge(sort: 'date', tail: 1)
  end

  def oldest_transaction(account = nil, opts = {})
    first_transaction account, opts.merge(sort: 'date', head: 1)
  end

  def first_transaction(*args)
    reg = register(*args)

    raise RRA::PTAConnection::AssertionError, 'Expected a single transaction' unless reg.transactions.length == 1

    reg.transactions.first
  end
end
