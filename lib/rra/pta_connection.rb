# frozen_string_literal: true

module RRA
  class PTAConnection
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
        converted = commodities.map do |a|
          begin
            # There are some outputs, which have no .code. And which only have
            # a quantity. We don't want to raise an exception for these, if
            # their quantity is zero, because that's still accumulateable.
            next if a.quantity.zero?

            a.alphabetic_code == currency.alphabetic_code ? a : pricer.convert(date.to_time, a, code)
          rescue RRA::Pricer::NoPriceError
            if ignore_unknown_codes
              # This seems to be what ledger does...
              nil
            else
              # This seems to be what we want...
              raise RRA::Pricer::NoPriceError
            end
          end
        end.compact

        # The case of [].sum will return an integer 0, which, isn't quite what
        # we want. At one point, we returned RRA::Journal::Commodity.from_symbol_and_amount(code, 0).
        # However, for some queries, this distorted the output to produce '$ 0.00', when we
        # really expected nil. This seems to be the best return, that way the caller can just ||
        # whatever they want, in the case they want to override this behavior.
        converted.empty? ? nil : converted.sum
      end
    end

    def command(*args)
      opts = args.pop if args.last.is_a? Hash
      open3_opts = {}
      if opts
        args += opts.map do |k, v|
          if k.to_sym == :from_s
            open3_opts[:stdin_data] = v
            %w[-f -]
          else
            [format('--%s', k.to_s), v == true ? nil : v] unless v == false
          end
        end.flatten.compact
      end

      is_logging = ENV.key?('RRA_LOG_COMMANDS') && !ENV['RRA_LOG_COMMANDS'].empty?

      cmd = ([bin_path] + args.collect { |a| Shellwords.escape a }).join(' ')

      time_start = Time.now if is_logging
      output, error, status = Open3.capture3 cmd, open3_opts
      time_end = Time.now if is_logging

      # Maybe We should send this to a RRA.logger.trace...
      if is_logging
        pretty_cmd = ([bin_path] + args).join(' ')

        puts format('(%.2<time>f elapsed) %<cmd>s', time: time_end - time_start, cmd: pretty_cmd)
      end

      unless status.success?
        raise StandardError, format('ledger exited non-zero (%<exitstatus>d): %<msg>s',
                                    exitstatus: status.exitstatus,
                                    msg: error)
      end

      output
    end

    def bin_path
      # Maybe we should support more than just /usr/bin...
      self.class::BIN_PATH
    end

    def adapter_name
      self.class.name.split(':').last.downcase.to_sym
    end
  end
end
