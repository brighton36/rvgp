require 'shellwords'

require_relative 'output'
require_relative '../pricer'

module RRA::Ledger
  LEDGER='/usr/bin/ledger'

  class AssertionError < StandardError
  end

  def self.balance(account, opts = {})
    RRA::Ledger::Output::Balance.new account, command(*opts_to_args(opts)+["xml"])
  end

  def self.register(*args)
    opts = (args.last.kind_of? Hash) ? args.pop : {}
    
    pricer = opts.delete :pricer
    
    RRA::Ledger::Output::Register.new command(*opts_to_args(opts)+["xml"]+args), 
      monthly: (opts[:monthly] == true), pricer: pricer
  end

  def self.command(*args)
    cmd = ([LEDGER]+args.collect{|a| Shellwords.escape a}).join(' ')
    # We should probably send this to a RRA.logger.trace...
    #pretty_cmd = ([LEDGER]+args).join(' ')
    IO.popen(cmd).read
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

  def self.opts_to_args(opts)
    opts.collect{|k, v| ['--%s' % [k.to_s], (v == true) ? nil : v] }.flatten.compact
  end

end
