require 'shellwords'
require 'open3'

require_relative 'output'
require_relative '../pricer'

module RRA::Ledger
  LEDGER='/usr/bin/ledger'

  class AssertionError < StandardError
  end

  def self.balance(account, opts = {})
    RRA::Ledger::Output::Balance.new account, command("xml", opts)
  end

  def self.register(*args)
    opts = (args.last.kind_of? Hash) ? args.pop : {}
    
    pricer = opts.delete :pricer
    
    RRA::Ledger::Output::Register.new command("xml", *args, opts), 
      monthly: (opts[:monthly] == true), pricer: pricer
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

    cmd = ([LEDGER]+args.collect{|a| Shellwords.escape a}).join(' ')

    # We should probably send this to a RRA.logger.trace...
    #pretty_cmd = ([LEDGER]+args).join(' ')

    output, error, status = Open3.capture3 cmd, open3_opts

    raise StandardError, "ledger exited non-zero (%d): %s" % [
      status.exitstatus, error] unless status.success?

    output
  end

  def self.path(relfile = nil)
    unless ENV.has_key? 'LEDGER_FILE'
      raise StandardError, "LEDGER_FILE environment variable is set incorrectly"
    end
    [File.dirname(ENV['LEDGER_FILE']),relfile].compact.join('/')
  end

  def self.newest_transaction(account = nil)
    first_transaction account, sort: 'date', tail: 1
  end

  def self.oldest_transaction(account = nil)
    first_transaction account, sort: 'date', head: 1
  end

  private

  def self.first_transaction(*args)
    reg = RRA::Ledger.register(*args)

    raise AssertionError, "Expected a single transaction" unless(
      reg.transactions.length == 1)

    reg.transactions.first
  end

end
