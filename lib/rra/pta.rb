# frozen_string_literal: true

module RRA
  # A base class, for use by plain text accounting adapters. Presumably for use with
  # hledger and ledger. This class contains abstractions and code shared by all Pta's.
  class Pta
    # This module is intended for use in clasess that wish to provide #ledger, #hledger,
    # and #pta methods, to instances.
    module AvailabilityHelper
      %w[ledger hledger pta].each do |attr|
        define_method(attr) { RRA::Pta.send attr }
      end
    end

    class AssertionError < StandardError
    end

    # This class provides shorthand, for classes whose public readers are populated via
    # #initialize().
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

    class BalanceAccount < RRA::Pta::ReaderBase
      readers :fullname, :amounts
    end

    class RegisterTransaction < ReaderBase
      readers :date, :payee, :postings
    end

    # A posting, as output by the 'register' command.
    class RegisterPosting < ReaderBase
      readers :account, :amounts, :totals, :tags

      def amount_in(code)
        commodities_sum amounts, code
      end

      def total_in(code)
        commodities_sum totals, code
      end

      private

      # Bear in mind that code/conversion is required, because the only reason
      # we'd have multiple amounts, is if we have multiple currencies.
      def commodities_sum(commodities, code)
        currency = RRA::Journal::Currency.from_code_or_symbol code

        pricer = options[:pricer] || RRA::Journal::Pricer.new
        # There's a whole section on default valuation behavior here :
        # https://hledger.org/hledger.html#valuation
        date = options[:price_date] || Date.today
        converted = commodities.map do |a|
          # There are some outputs, which have no .code. And which only have
          # a quantity. We don't want to raise an exception for these, if
          # their quantity is zero, because that's still accumulateable.
          next if a.quantity.zero?

          a.alphabetic_code == currency.alphabetic_code ? a : pricer.convert(date.to_time, a, code)
        rescue RRA::Journal::Pricer::NoPriceError
          # This seems to be what we want...
          raise RRA::Journal::Pricer::NoPriceError
        end.compact

        # The case of [].sum will return an integer 0, which, isn't quite what
        # we want. At one point, we returned RRA::Journal::Commodity.from_symbol_and_amount(code, 0).
        # However, for some queries, this distorted the output to produce '$ 0.00', when we
        # really expected nil. This seems to be the best return, that way the caller can just ||
        # whatever they want, in the case they want to override this behavior.
        converted.empty? ? nil : converted.sum
      end
    end

    # Somehow, it turned out that both hledger and ledger were similar enough, that I could abstract
    # this here....
    def stats(*args)
      args, opts = args_and_opts(*args)
      # TODO: This should get its own error class...
      raise StandardError, "Unexpected argument(s) : #{args.inspect}" unless args.empty?

      command('stats', opts).scan(/^\n? *(?:([^:]+?)|(?:([^:]+?) *: *(.*?))) *$/).each_with_object([]) do |match, sum|
        if match[0]
          sum.last[1] = [sum.last[1]] unless sum.last[1].is_a?(Array)
          sum.last[1] << match[0]
        else
          sum << [match[1], match[2].empty? ? [] : match[2]]
        end
        sum
      end.to_h
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
        raise StandardError, format('%<adapter_name>s exited non-zero (%<exitstatus>d): %<msg>s',
                                    adapter_name: adapter_name,
                                    exitstatus: status.exitstatus,
                                    msg: error)
      end

      output
    end

    def args_and_opts(*args)
      opts = args.last.is_a?(Hash) ? args.pop : {}

      if ledger?
        opts.delete :hledger_opts
        opts.delete :hledger_args

        args += opts.delete(:ledger_args) if opts.key? :ledger_args
        opts.merge! opts.delete(:ledger_opts) if opts.key? :ledger_opts
      elsif hledger?
        opts.delete :ledger_opts
        opts.delete :ledger_args

        args += opts.delete(:hledger_args) if opts.key? :hledger_args
        opts.merge! opts.delete(:hledger_opts) if opts.key? :hledger_opts
      end

      [args, opts]
    end

    def present?
      File.executable? bin_path
    end

    def bin_path
      # Maybe we should support more than just /usr/bin...
      self.class::BIN_PATH
    end

    def adapter_name
      self.class.name.split(':').last.downcase.to_sym
    end

    def ledger?
      adapter_name == :ledger
    end

    def hledger?
      adapter_name == :hledger
    end

    class << self
      def ledger
        Ledger.new
      end

      def hledger
        HLedger.new
      end

      def pta
        @pta ||= if @pta_adapter
                   send @pta_adapter
                 elsif ledger.present?
                   ledger
                 elsif hledger.present?
                   hledger
                 else
                   raise StandardError, 'No pta adapter specified, or detected, on system'
                 end
      end

      def pta_adapter=(driver)
        @pta = nil
        @pta_adapter = driver.to_sym
      end
    end
  end
end
