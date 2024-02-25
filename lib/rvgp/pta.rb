# frozen_string_literal: true

require_relative 'base/reader'

module RRA
  # A base class, which offers functionality to plain text accounting adapters. At the moment,
  # that means either 'ledger', or 'hledger'. This class contains abstractions and code shared
  # by the {RRA::Pta::HLedger} and {RRA::Pta::Ledger} classes.
  #
  # In addition, this class contains the {RRA::Pta::AvailabilityHelper}, which can be included
  # by any class, in order to offer shorthand access to this entire suite of functions.
  class Pta
    # This module is intended for use in classes that wish to provide #ledger, #hledger,
    # and #pta methods, to its instances.
    module AvailabilityHelper
      # (see RRA::Pta.ledger)
      def ledger
        RRA::Pta.ledger
      end

      # (see RRA::Pta.hledger)
      def hledger
        RRA::Pta.hledger
      end

      # (see RRA::Pta.pta)
      def pta
        RRA::Pta.pta
      end
    end

    # This error is raised when a Sanity check fails. This should never happen.
    class AssertionError < StandardError
    end

    # This class stores the Account details, as produced by the balance method of a pta adapter
    # @attr_reader fullname [String] The name of this account
    # @attr_reader amounts [Array<RRA::Journal::Commodity>] The commodities in this account, as reported by balance
    class BalanceAccount < RRA::Base::Reader
      readers :fullname, :amounts
      # TODO: Implement and test the :pricer here
    end

    # This class stores the Transaction details, as produced by the register method of a pta adapter
    # @attr_reader date [Date] The date this transaction occurred
    # @attr_reader payee [String] The payee (aka description) line of this transaction
    # @attr_reader postings [Array<RRA::Pta::RegisterTransaction>] The postings in this transaction
    class RegisterTransaction < RRA::Base::Reader
      readers :date, :payee, :postings
    end

    # A posting, as output by the 'register' command. Typically these are available as items in a
    # transaction, via the {RRA::Pta::RegisterTransaction#postings} method.
    # @attr_reader account [String] The account this posting was assigned to
    # @attr_reader amounts [Array<RRA::Journal::Commodity>] The commodities that were encountered in the amount column
    # @attr_reader totals [Array<RRA::Journal::Commodity>] The commodities that were encountered in the total column
    # @attr_reader tags [Hash<String,<String,TrueClass>>] A hash containing the tags that were encountered in this
    #                                                     posting. Values are either the string that was encountered,
    #                                                     for this tag. Or, true, if no specific string value was
    #                                                     assigned
    class RegisterPosting < RRA::Base::Reader
      readers :account, :amounts, :totals, :tags

      # This method will return the sum of all commodities in the amount column, in the specified currency.
      # @param [String] code A three digit currency code, or currency symbol, in which you want to express the amount
      # @return [RRA::Journal::Commodity] The amount column, expressed as a sum
      def amount_in(code)
        commodities_sum amounts, code
      end

      # This method will return the sum of all commodities in the total column, in the specified currency.
      # @param [String] code A three digit currency code, or currency symbol, in which you want to express the total
      # @return [RRA::Journal::Commodity] The total column, expressed as a sum
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

    # Returns the output of the 'stats' command, parsed into key/value pairs.
    # @param [Array<Object>] args Arguments and options, passed to the pta command. See {RRA::Pta#args_and_opts} for
    #                             details
    # @return [Hash<String, <String,Array<String>>>] The journal statistics. Values are either a string, or an array
    #                                                of strings, depending on what was output.
    def stats(*args)
      # Somehow, it turned out that both hledger and ledger were similar enough, that I could abstract
      # this here....
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

    # Returns the output of arguments to a pta adapter.
    #
    # *NOTE:* If the RRA_LOG_COMMANDS environment variable is set. (say, to "1") this command will output diagnostic
    # information to the console. This information will include the fully expanded command being run,
    # alongside its execution time.
    #
    # While args and options are largely fed straight to the pta command, for processing, we support the following
    # options, which, are removed from the arguments, and handled in this method.
    # - *:from_s* (String)- If a string is provided here, it's fed to the STDIN of the pta adapter. And "-f -" is added
    #   to the program's arguments. This instructs the command to treat STDIN as a journal.
    #
    # @param [Array<Object>] args Arguments and options, passed to the pta command. See {RRA::Pta#args_and_opts} for
    #                             details
    # @return [String] The output of a pta executable
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

    # Given a splatted array, groups and returns arguments into an array of commands, and a hash of options. Options,
    # are expected to be provided as a Hash, as the last element of the splat.
    #
    # Most of the public methods in a Pta adapter, have largely-undefined arguments. This is because these methods
    # mostly just pass their method arguments, straight to ledger and hledger for handling. Therefore, the 'best'
    # place to find documentation on what arguments are supported, is the man page for hledger/ledger. The reason
    # most of the methods exist (#balance, #register, etc), in a pta adapter, are to control how the output of the
    # command is parsed.
    #
    # Here are some examples of how arguments are sent straight to a pta command:
    # - ledger.balance('Personal:Expenses', file: '/tmp/test.journal') becomes:
    #   /usr/bin/ledger xml Personal:Expenses --file /tmp/test.journal
    # - pta.register('Income', monthly: true) becomes:
    #   /usr/bin/ledger xml Income --sort date --monthly
    #
    # That being said - there are some options that don't get passed directly to the pta command. Most of these
    # options are documented below.
    #
    # This method also supports the following options, for additional handling:
    # - *:hledger_args* - If this is a ledger adapter, this option is removed. Otherwise, the values of this Array will
    #   be returned in the first element of the return array.
    # - *:hledger_opts* - If this is a ledger adapter, this option is removed. Otherwise, the values of this Hash will
    #   be merged with the second element of the return array.
    # - *:ledger_args* - If this is an hledger adapter, this option is removed. Otherwise, the values of this Array will
    #   be returned in the first element of the return array.
    # - *:ledger_opts* - If this is an hledger adapter, this option is removed. Otherwise, the values of this Hash will
    #   be merged with the second element of the return array.
    # @return [Array<Object>] A two element array. The first element of this array is an Array<String> containing the
    #                         string arguments that were provided to this method, and/or which should be passed directly
    #                         to a pta shell command function. The second element of this array is a
    #                         Hash<Symbol, Object> containing the options that were provided to this method, and which
    #                         should be passed directly to a pta shell command function.
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

    # Determines whether this adapter is found in the expected path, and is executable
    # @return [TrueClass, FalseClass] True if we can expect this adapter to execute
    def present?
      File.executable? bin_path
    end

    # The path to this adapter's binary
    # @return [String] The path in the filesystem, where this pta bin is located
    def bin_path
      # Maybe we should support more than just /usr/bin...
      self.class::BIN_PATH
    end

    # The name of this adapter, either :ledger or :hledger
    # @return [Symbol] The adapter name, in a shorthand form. Downcased, and symbolized.
    def adapter_name
      self.class.name.split(':').last.downcase.to_sym
    end

    # Indicates whether or not this is a ledger pta adapter
    # @return [TrueClass, FalseClass] True if this is an instance of {RRA::Pta::Ledger}
    def ledger?
      adapter_name == :ledger
    end

    # Indicates whether or not this is a hledger pta adapter
    # @return [TrueClass, FalseClass] True if this is an instance of {RRA::Pta::HLedger}
    def hledger?
      adapter_name == :hledger
    end

    class << self
      # Return a new instance of RRA::Pta::Ledger
      # @return [RRA::Pta::Ledger]
      def ledger
        Ledger.new
      end

      # Return a new instance of RRA::Pta::HLedger
      # @return [RRA::Pta::HLedger]
      def hledger
        HLedger.new
      end

      # Depending on what's installed and configured, a pta adapter is returned.
      # The rules that govern what adapter is choosen, works like this:
      # 1. If {Pta.pta_adapter=} has been set, then, this adapter will be returned.
      # 2. If ledger is installed on the system, then ledger is returned
      # 3. If hledger is installed on the system, then hledger is returned
      # If no pta adapters are available, an error is raised.
      # @return [RRA::Pta::Ledger,RRA::Pta::HLedger]
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

      # Override the default adapter, used by {RRA::Pta.pta}.
      # This can be set to one of: nil, :hledger, or :ledger.
      # @param [Symbol] driver The adapter name, in a shorthand form. Downcased, and symbolized.
      # @return [void]
      def pta_adapter=(driver)
        @pta = nil
        @pta_adapter = driver.to_sym
      end
    end
  end
end
