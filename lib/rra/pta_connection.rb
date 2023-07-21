# frozen_string_literal: true

module RRA
  class PTAConnection
    class AssertionError < StandardError
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

    # TODO: Maybe we should support more than just /usr/bin...
    def self.bin_path
      self::BIN_PATH
    end

    # TODO: I think we should pull this path from the config.primary_journal_path ...
    def self.path(relfile = nil)
      unless ENV.has_key? 'LEDGER_FILE'
        raise StandardError, "LEDGER_FILE environment variable is set incorrectly"
      end
      [File.dirname(ENV['LEDGER_FILE']),relfile].compact.join('/')
    end
  end
end
