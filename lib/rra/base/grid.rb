# frozen_string_literal: true

require 'csv'
require_relative '../descendant_registry'
require_relative '../utilities'

module RRA
  module Base
    # The base class implementation, for application-defined grids. This class
    # offers the bulk of functionality that grids use, in order to turn queries
    # into csv files, in the project build directory.
    #
    # Users are expected to inherit from this class, with their grid bulding
    # implementations, inside the app/grids directory. This class offers helpers
    # for working with pta_adapters (particularly for use with by-month queries)
    # as well as code to detect and produce the annual segmentation of grids, and
    # multiple-sheet segmentation of grids.
    class Grid
      include RRA::DescendantRegistry
      include RRA::PtaAdapter::AvailabilityHelper
      include RRA::Utilities

      register_descendants RRA, :grids, accessors: {
        task_names: lambda { |registry|
          registry.names.map do |name|
            RRA.app.config.grid_years.map do |year|
              format 'grid:%<year>d-%<name>s', year: year, name: name.tr('_', '-')
            end
          end.flatten
        }
      }

      attr_reader :starting_at, :ending_at, :year

      # TODO: This default, should maybe come from RRA.app..
      def initialize(starting_at, ending_at)
        # NOTE: It seems that with monthly queries, the ending date works a bit
        # differently. It's not necessariy to add one to the day here. If you do,
        # you get the whole month of January, in the next year added to the output.
        @year = starting_at.year
        @starting_at = starting_at
        @ending_at = ending_at
      end

      def to_file!
        write! self.class.output_path(year), to_table
        nil
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
        opts = args.last.is_a?(Hash) ? args.pop : {}

        in_code = opts[:in_code] || '$'

        reduce_postings_by_month(*args, opts) do |sum, date, posting|
          next sum if posting.account.nil? || posting.account.is_a?(Symbol)

          amount_in_code = posting.send posting_method, in_code
          if amount_in_code
            sum[posting.account] ||= {}
            if sum[posting.account].key? date
              sum[posting.account][date] += amount_in_code
            else
              sum[posting.account][date] = amount_in_code
            end
          end
          sum
        end
      end

      def reduce_monthly(*args, posting_method)
        opts = args.last.is_a?(Hash) ? args.pop : {}

        in_code = opts[:in_code] || '$'

        opts[:ledger_opts] ||= {}
        opts[:ledger_opts][:collapse] ||= true

        opts[:hledger_args] ||= []
        opts[:hledger_args] << 'depth:0' unless (args + opts[:hledger_args]).any? { |arg| /^depth:\d+$/.match arg }

        reduce_postings_by_month(*args, opts) do |sum, date, posting|
          amount_in_code = posting.send(posting_method, in_code)
          if amount_in_code
            if sum[date]
              sum[date] += amount_in_code
            else
              sum[date] = amount_in_code
            end
          end
          sum
        end
      end

      # This method keeps our grids DRY. It accrues a sum for each posting, on a
      # monthly query
      def reduce_postings_by_month(*args, &block)
        opts = args.last.is_a?(Hash) ? args.pop : {}

        initial = opts.delete(:initial) || {}

        # TODO: I've never been crazy about this name... maybe we can borrow terminology
        # from the hledger help, on what historical is...
        accrue_before_begin = opts.delete :accrue_before_begin

        opts.merge!({ pricer: RRA.app.pricer,
                      monthly: true,
                      empty: false, # This applies to Ledger, and ensures it's results match HLedger's exactly
                      # TODO: I don't think I need this fgile: here
                      file: RRA.app.config.project_journal_path })

        opts[:hledger_opts] ||= {}
        opts[:ledger_opts] ||= {}
        opts[:hledger_args] ||= []

        if accrue_before_begin
          opts[:ledger_opts][:display] = format('date>=[%<starting_at>s] and date <=[%<ending_at>s]',
                                                starting_at: starting_at.strftime('%Y-%m-%d'),
                                                ending_at: ending_at.strftime('%Y-%m-%d'))
          # TODO: Can we maybe use opts on this?
          opts[:hledger_args] += [format('date:%s-', starting_at.strftime('%Y/%m/%d')),
                                  format('date:-%s', ending_at.strftime('%Y/%m/%d'))]
          opts[:hledger_opts][:historical] = true
        else
          # NOTE: I'm not entirely sure we want this path. It may be that we should always use the
          # display option....
          opts[:begin] = (opts[:begin] || starting_at).strftime('%Y-%m-%d')
          # It seems that ledger interprets the --end parameter as :<, and hledger
          # interprets it as :<= . So, we add one here, and, this makes the output consistent with
          # hledger, as well as our :display syntax above.
          opts[:ledger_opts][:end] = (ending_at + 1).strftime('%Y-%m-%d')
          opts[:hledger_opts][:end] = ending_at.strftime('%Y-%m-%d')
        end

        pta_adapter.register(*args, opts).transactions.inject(initial) do |ret, tx|
          tx.postings.reduce(ret) do |sum, posting|
            block.call sum, tx.date, posting
          end
        end
      end

      def write!(path, rows)
        CSV.open(path, 'w') do |csv|
          rows.each do |row|
            csv << row.map { |val| val.is_a?(RRA::Journal::Commodity) ? val.to_s(no_code: true, precision: 2) : val }
          end
        end
      end

      class << self
        include RRA::Utilities
        include RRA::PtaAdapter::AvailabilityHelper

        attr_reader :name, :description, :output_path_template

        def grid(name, description, status_name_template, options = {})
          @name = name
          @description = description
          @status_name_template = status_name_template
          @output_path_template = options[:output_path_template]
        end

        def dependency_paths
          # NOTE: This is only used right now, in the plot task. So, the cache is fine.
          # But, if we start using this before the journals are built, we're going to
          # need to clear this cache, thereafter. So, maybe we want to take a parameter
          # here, or figure something out then, to prevent problems.
          @dependency_paths ||= pta_adapter.files(file: RRA.app.config.project_journal_path)
        end

        def uptodate?(year)
          FileUtils.uptodate? output_path(year), dependency_paths
        end

        def output_path(year)
          raise StandardError, 'Missing output_path_template' unless output_path_template

          [RRA.app.config.build_path('grids'), '/', output_path_template % year, '.csv'].join
        end

        def status_name(year)
          @status_name_template % year
        end
      end

      # This module can be included into children of RRA::Base::Grid, in order to add support
      # for multiple sheets, per year. This module contains class and instance helpers, that
      # will extend the RRA::Base::Grid syntax for year segmentation, into additional segments. These
      # segments can be defined by including classes, using the #has_sheets method in their
      # class. For example:
      # ```
      #   has_sheets('cashflow') { %w(personal business) }
      # ```
      # will facilitate the creation of "#{year}-cashflow-business.csv" and
      # "#{year}-cashflow-personal.csv" grids, in the project's build/grids output.
      module HasMultipleSheets
        def to_table(sheet)
          [sheet_header(sheet)] + sheet_body(sheet)
        end

        def to_file!
          self.class.sheets(year).each do |sheet|
            write! self.class.output_path(year, sheet.to_s.downcase), to_table(sheet)
          end
          nil
        end

        def sheets(year)
          self.class.sheets year
        end

        def self.included(klass)
          klass.extend ClassMethods
        end

        # This module contains the Class methods, that are automatically included,
        # at the time RRA::Base::Grid::HasMultipleSheets is included into a class.
        module ClassMethods
          def has_sheets(sheet_output_prefix, &block) # rubocop:disable Naming/PredicateName
            @has_sheets = block
            @sheet_output_prefix = sheet_output_prefix
          end

          def sheets(year)
            @sheets ||= {}
            @sheets[year] ||= @has_sheets.call year
          end

          def sheet_output_prefix
            @sheet_output_prefix
          end

          def output_path(year, sheet)
            format '%<path>s/%<year>s-%<prefix>s-%<sheet>s.csv',
                   path: RRA.app.config.build_path('grids'),
                   year: year,
                   prefix: sheet_output_prefix,
                   sheet: sheet.to_s.downcase
          end

          def uptodate?(year)
            sheets(year).all? do |sheet|
              FileUtils.uptodate? output_path(year, sheet), dependency_paths
            end
          end
        end
      end
    end
  end
end
