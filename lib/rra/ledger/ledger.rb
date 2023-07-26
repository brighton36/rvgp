# frozen_string_literal: true

require 'shellwords'
require 'open3'

require_relative 'output'
require_relative '../pricer'
require_relative '../pta_connection'

class RRA::Ledger < RRA::PTAConnection
  BIN_PATH = '/usr/bin/ledger'

  def self.balance(account, opts = {})
    RRA::Ledger::Output::Balance.new account, command('xml', opts)
  end

  def self.register(*args)
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

  def self.newest_transaction(account = nil, opts = {})
    first_transaction account, opts.merge(sort: 'date', tail: 1)
  end

  def self.oldest_transaction(account = nil, opts = {})
    first_transaction account, opts.merge(sort: 'date', head: 1)
  end

  def self.first_transaction(*args)
    reg = RRA::Ledger.register(*args)

    raise RRA::PTAConnection::AssertionError, 'Expected a single transaction' unless reg.transactions.length == 1

    reg.transactions.first
  end
end
