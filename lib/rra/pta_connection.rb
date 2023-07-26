# frozen_string_literal: true

module RRA
  class PTAConnection
    # NOTE: I think the goal of this class, would be for #initialize to return
    # a pipe that stays open. Which, ledger supports (I think, just run it w/o
    # a command), but which hledger does not...
    # We may just want to not make this a class, though. I don't know yet.
    # Maybe initialize should take the LEDGER_FILE... and we move these
    # methods to instances

    class AssertionError < StandardError
    end

    class ReaderBase
      def self.readers(*readers)
        attr_reader(*readers)
        attr_reader :options

        define_method :initialize do |*args|
          readers.each_with_index do |r, i|
            instance_variable_set format('@%s', r).to_sym, args[i]
          end

          # If there are more arguments than attr's the last argument is an options
          # hash
          instance_variable_set '@options', args[readers.length].is_a?(Hash) ? args[readers.length] : {}
        end
      end
    end

    class BalanceAccount < RRA::PTAConnection::ReaderBase
      readers :fullname, :amounts
    end

    class RegisterTransaction < ReaderBase
      readers :date, :payee, :postings
    end

    class RegisterPosting < ReaderBase
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

    def self.command(*args)
      opts = args.pop if args.last.kind_of? Hash
      open3_opts = {}
      args += opts.collect{|k, v|
        if k.to_sym == :from_s
          open3_opts[:stdin_data] = v
          ['-f', '-']
        else
          ['--%s' % [k.to_s], (v == true) ? nil : v]
        end
        }.flatten.compact if opts

      cmd = ([bin_path]+args.collect{|a| Shellwords.escape a}).join(' ')

      # We should probably send this to a RRA.logger.trace...
      pretty_cmd = ([bin_path]+args).join(' ')

      output, error, status = Open3.capture3 cmd, open3_opts

      raise StandardError, "ledger exited non-zero (%d): %s" % [
        status.exitstatus, error] unless status.success?

      output
    end

    def self.bin_path
      # Maybe we should support more than just /usr/bin...
      self::BIN_PATH
    end

    # TODO: I think we should pull this path from the config.primary_journal_path ...
    #       but, let's take that in an #initialize(), and stop with this class method nonsense
    def self.path(relfile = nil)
      unless ENV.has_key? 'LEDGER_FILE'
        raise StandardError, "LEDGER_FILE environment variable is set incorrectly"
      end
      [File.dirname(ENV['LEDGER_FILE']),relfile].compact.join('/')
    end
  end
end
