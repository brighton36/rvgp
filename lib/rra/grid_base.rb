require 'csv'
require_relative 'descendant_registry'
require_relative 'utilities'

class RRA::GridBase
  include RRA::DescendantRegistry

  include RRA::Utilities

  register_descendants RRA, :grids, accessors: {
    task_names: lambda{|registry| 
      registry.names.collect{|name| 
        RRA.app.config.grid_years.collect{|year| 'grid:%d-%s' % [year,name.tr('_', '-')]}
      }.flatten
    }
  }

  attr_reader :starting_at, :ending_at, :year

  def initialize(starting_at, ending_at)
    # NOTE: It seems that with monthly queries, the ending date works a bit
    # differently. It's not necessariy to add one to the day here. If you do,
    # you get the whole month of January, in the next year added to the output.
    @year, @starting_at, @ending_at = starting_at.year, starting_at, ending_at
  end

  def to_file!
    write! self.class.output_path(year), to_table 
    return  nil
  end

  def to_table
    [sheet_header] + sheet_body
  end

  private

  def monthly_totals_by_account(*args)
    reduce_monthly_by_account(*args, :total_in)
  end

  def monthly_amounts_by_account(*args)
    reduce_monthly_by_account(*args, :amount_in)
  end

  def monthly_totals(*args)
    reduce_monthly(*args, :total_in)
  end

  def monthly_amounts(*args)
    reduce_monthly(*args, :amount_in)
  end

  def reduce_monthly_by_account(*args, posting_method)
    opts = args.last.kind_of?(Hash) ? args.pop : {}

    in_code = opts[:in_code] || '$'

    reduce_postings_by_month(*args, opts) do |sum, date, posting|
      next sum if posting.account.nil? || posting.account.is_a?(Symbol)

      sum[posting.account] ||= {}
      sum[posting.account][date] ||= RRA::Journal::Commodity.from_symbol_and_amount in_code, 0
      sum[posting.account][date] += posting.send(posting_method, in_code) 
      sum
    end
  end

  def reduce_monthly(*args, posting_method)
    opts = args.last.kind_of?(Hash) ? args.pop : {}

    in_code = opts[:in_code] || '$'
    opts[:collapse] = true unless opts.has_key? :collapse

    reduce_postings_by_month(*args, opts) do |sum, date, posting|
      sum[date] ||= RRA::Journal::Commodity.from_symbol_and_amount in_code, 0
      sum[date] += posting.send(posting_method, in_code)
      sum
    end
  end

  # This method keeps our grids DRY. It accrues a sum for each posting, on a
  # monthly query
  def reduce_postings_by_month(*args, &block)
    opts = args.last.kind_of?(Hash) ? args.pop : {}

    ledger_opts = { pricer: RRA.app.pricer,
                    monthly: true,
                    empty: true,
                    file: RRA.app.config.project_journal_path }

    ledger_opts[:collapse] = opts[:collapse] if opts[:collapse]

    if opts[:accrue_before_begin]
      ledger_opts[:display] = format('date>=[%<starting_at>s] and date <=[%<ending_at>s]',
                                     starting_at: starting_at.strftime('%Y-%m-%d'),
                                     ending_at: ending_at.strftime('%Y-%m-%d'))
    else
      # NOTE: I'm not entirely sure we want this path. It may be that we should always use the
      # display option....
      ledger_opts[:begin] = (opts[:begin] ? opts[:begin] :
        starting_at).strftime('%Y-%m-%d')
      ledger_opts[:end] = ending_at.strftime('%Y-%m-%d')
    end

    initial = opts[:initial] || Hash.new

    RRA::Ledger.register(*args, ledger_opts).transactions.inject(initial) do |ret, tx|
      tx.postings.reduce(ret) do |sum, posting|
        block.call sum, tx.date, posting
      end
    end
  end

  def write!(path, rows)
    CSV.open(path, "w") do |csv| 
      rows.each do |row|
        csv << row.collect{ |val| val.kind_of?(RRA::Journal::Commodity) ? 
          val.to_s(no_code: true, precision: 2) : val }
      end
    end
  end

  class << self
    include RRA::Utilities

    attr_reader :name, :description
    attr_reader :output_path_template

    def grid(name, description, status_name_template, options = {})
      @name, @description, @status_name_template = name, description, 
        status_name_template
      @output_path_template = options[:output_path_template]
    end

    def dependency_paths
      # NOTE: This is only used right now, in the plot task. So, the cache is fine.
      # But, if we start using this before the journals are built, we're going to
      # need to clear this cache, thereafter. So, maybe we want to take a parameter
      # here, or figure something out then, to prevent problems.
      @dependency_paths ||= RRA::HLedger.files(file: RRA.app.config.project_journal_path)
    end

    def uptodate?(year)
      FileUtils.uptodate? output_path(year), dependency_paths
    end

    def output_path(year)
      raise StandardError, "Missing output_path_template" unless output_path_template
      "%s/%s.csv" % [RRA.app.config.build_path('grids'), output_path_template % year]
    end

    def status_name(year)
      @status_name_template % year
    end
  end
end

module RRA::GridBase::HasMultipleSheets

  def to_table(sheet)
    [sheet_header(sheet)] + sheet_body(sheet)
  end

  def to_file!
    self.class.sheets(year).each do |sheet|
      write! self.class.output_path(year, sheet.to_s.downcase), to_table(sheet)
    end
    return nil
  end

  def sheets(year)
    self.class.sheets year
  end

  def self.included(klass)
    klass.extend ClassMethods
  end

  module ClassMethods
    def has_sheets(sheet_output_prefix, &block)
      @has_sheets, @sheet_output_prefix = block, sheet_output_prefix
    end

    def sheets(year)
      @sheets ||= {}
      @sheets[year] ||= @has_sheets.call year
    end

    def sheet_output_prefix
      @sheet_output_prefix
    end

    def output_path(year, sheet)
      "%s/%s-%s-%s.csv" % [RRA.app.config.build_path('grids'), year,
        sheet_output_prefix, sheet.to_s.downcase]
    end

    def uptodate?(year)
      sheets(year).all? do |sheet|
        FileUtils.uptodate? output_path(year, sheet), dependency_paths
      end
    end
  end
end
