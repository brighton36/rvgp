require 'nokogiri'
require_relative '../pta_connection'

class RRA::Ledger < RRA::PTAConnection
  module Output
    class XmlBase
      class Commodity < RRA::PTAConnection::ReaderBase
        readers :symbol, :date, :price
      end

      attr_reader :doc, :commodities, :pricer, :options

      def initialize(xml, options)
        @doc = Nokogiri::XML xml, &:noblanks
        @pricer = options[:pricer] || RRA::Pricer.new

        @commodities = doc.search(
          '//commodities//commodity[annotation]').collect{ |xcommodity| 

          next unless ['symbol', 'date', 'price', 'price/commodity/symbol',
            'price/quantity'].all?{|path| xcommodity.at(path) }

          symbol = xcommodity.at('symbol').content
          date = Date.strptime(xcommodity.at('date').content, '%Y/%m/%d')
          commodity = RRA::Journal::Commodity.from_symbol_and_amount(
            xcommodity.at('price/commodity/symbol').content, 
            xcommodity.at('price/quantity').content)

          @pricer.add date.to_time, symbol, commodity
          Commodity.new symbol, date, commodity 
        }
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

        return nil unless xaccounts
      
        @accounts = xaccounts.collect{ |xaccount| 
          account = RRA::PTAConnection::BalanceAccount.new( xaccount.at('fullname').content,
            xaccount.xpath('account-amount/amount|account-amount/*/amount').collect{|amount| 
              commodity = RRA::Journal::Commodity.from_symbol_and_amount(
                amount.at('symbol').content, amount.at('quantity').content
              ) 
              commodity if commodity.quantity != 0
            }.compact) 
          account if [ /#{Regexp.escape(needle)}/.match(account.fullname),
           (account.amounts.length > 0) ].all?
        }.compact
      end
    end

    class Register < XmlBase
      attr_reader :transactions

      def initialize(xml, options = {})
        super xml, options

        @transactions = doc.xpath('//transactions/transaction').collect{|xt|
          date = Date.strptime(xt.at('date').content, '%Y/%m/%d')

          RRA::PTAConnection::RegisterTransaction.new date,
            xt.at('payee').content,
            xt.xpath('postings/posting').collect{|xp|
              amounts, totals = *['post-amount', 'total'].collect{|attr|
                xp.at(attr).search('amount').collect{|xa| 
                  RRA::Journal::Commodity.from_symbol_and_amount(
                    xa.at('commodity/symbol')&.content,
                    xa.at('quantity').content) }
                }

              account = xp.at('account/name').content

              # This phenomenon of '<None>' and '<total>', seems to only happen
              # when the :empty parameter is passed.
              if options[:translate_meta_accounts]
                case account
                when '<None>' then account = nil
                when '<Total>' then account = :total
                end
              end

              RRA::PTAConnection::RegisterPosting.new account, amounts, totals,
                Hash[xp.search('metadata/value').collect{|xvalue| 
                  [xvalue['key'], xvalue.content]}],
                pricer: pricer, price_date: (options[:monthly]) ? 
                  # This sets our date to the end -of the month, if this is a
                  # monthly query
                  Date.new(date.year, date.month, -1) : date
            }
        }
      end
    end
  end
end
