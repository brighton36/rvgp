require 'nokogiri'
require_relative '../pta_connection'

class RRA::Ledger < RRA::PTAConnection
  module Output
    class ReaderBase
      def self.readers(*readers)
        attr_reader *readers
        attr_reader :options

        define_method :initialize do |*args|
          readers.each_with_index do |r, i| 
            instance_variable_set ('@%s' % r).to_sym, args[i]
          end

          # If there are more arguments than attr's the last argument is an options
          # hash
          instance_variable_set :'@options', 
            args[readers.length].kind_of?(Hash) ? args[readers.length] : Hash.new
        end
      end

    end

    class XmlBase
      class Commodity < ReaderBase
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
      class Account < ReaderBase
        readers :fullname, :amounts
      end
      
      attr_reader :accounts

      def initialize(needle, xml, options = {})
        super xml, options

        # Bear in mind that this query is slightly odd, in that account is nested
        # So, I stipulate that we are at the end of a nest "not account" and 
        # have children "*"
        xaccounts = doc.xpath('//accounts//account[not(account) and *]')

        return nil unless xaccounts
      
        @accounts = xaccounts.collect{ |xaccount| 
          account = Account.new( xaccount.at('fullname').content, 
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
      class Transaction < ReaderBase
        readers :date, :payee, :postings
      end

      class Posting < ReaderBase
        readers :account, :amounts, :totals, :tags

        def amount_in(code, ignore_unknown_codes = false)
          commodities_sum amounts, code, ignore_unknown_codes
        end

        def total_in(code, ignore_unknown_codes = false)
          commodities_sum totals, code, ignore_unknown_codes
        end

        private

        # Bear in mind that code/conversion is required, because the only reason
        # we'd have multiple amounts, is if we have multiple currencies.
        def commodities_sum(commodities, code, ignore_unknown_codes)
          currency = RRA::Journal::Currency.from_code_or_symbol code

          pricer = options[:pricer] || RRA::Pricer.new
          # There's a whole section on default valuation behavior here : 
          # https://hledger.org/hledger.html#valuation
          date = options[:price_date] || Date.today
          converted = commodities.collect{|a|
            begin
              # There are some outputs, which have no .code. And which only have
              # a quantity. We don't want to raise an exception for these, if
              # their quantity is zero, because that's still accumulateable.
              next if a.quantity == 0

              (a.alphabetic_code != currency.alphabetic_code) ?
                pricer.convert(date.to_time, a, code) : a
            rescue RRA::Pricer::NoPriceError
              if ignore_unknown_codes
                # This seems to be what ledger does...
                nil
              else
                # This seems to be what we want...
                raise RRA::Pricer::NoPriceError
              end
            end
          }.compact

          # The case of [].sum will return an integer 0, which, isn't quite what
          # we want...
          converted.empty? ? RRA::Journal::Commodity.from_symbol_and_amount(code, 0) : converted.sum
        end
      end

      attr_reader :transactions

      def initialize(xml, options = {})
        super xml, options

        @transactions = doc.xpath('//transactions/transaction').collect{|xt|
          date = Date.strptime(xt.at('date').content, '%Y/%m/%d')

          Transaction.new date, 
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

              Posting.new account, amounts, totals,
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
