# frozen_string_literal: true

require 'csv'
require_relative '../application/descendant_registry'
require_relative '../utilities'

module RRA
  # This module largely exists as a folder, in which to group Parent classes, that are used throughout the project.
  # There's nothing else interesting happening here in this module, other than its use as as namespace.
  # @!visibility private
  module Base
    # This is the base class implementation, for your application-defined grids. This class offers the bulk of
    # functionality that your grids will use. The goal of a grid, is to compute csv files, in the project's build/grids
    # directory. Sometimes, these grids will simply be an assemblage of pta queries. Other times, these grids won't
    # involve any pta queries at all, and may instead contain projections and statistics computed elsewhere.
    #
    # Users are expected to inherit from this class, in their grid bulding implementations, inside ruby classes defined
    # in your project's app/grids directory. This class offers helpers for working with pta_adapters (particularly for
    # use with by-month queries). Additionally, this class offers code to detect and produce annual, and otherwise
    # arbitary(see {RRA::Base::Grid::HasMultipleSheets}) segmentation of grids.
    #
    # The function and purpose of grids, in your project, is as follows:
    # - Store a state of our data in the project's build, and thus its git history.
    # - Provide the data used by a subsequent {RRA::Plot}.
    # - Provide the data used by a subsequent {RRA::Utilities::GridQuery}.
    #
    # Each instance of Grid, in your build is expected to represent a segment of the data. Typically this segment will
    # be as simple as a date range (either a specific year, or 'all dates'). However, the included
    # {RRA::Base::Grid::HasMultipleSheets} module, allows you to add additional arbitrary segments (perhaps a segment
    # for each value of a tag), that may be used to produce additional grids in your build, on top of the dated
    # segments.
    #
    # = Example
    # Perhaps the easiest way to understand what this class does, is to look at one of the sample grids produced by
    # the new_project command. Here's the contents of an app/grids/wealth_growth_grid.rb, that you can use in your
    # projects:
    #    class WealthGrowthGrid < RRA::Base::Grid
    #      grid 'wealth_growth', 'Generate Wealth Growth Grids', 'Wealth Growth by month (%s)',
    #           output_path_template: '%s-wealth-growth'
    #
    #      def sheet_header
    #        %w[Date Assets Liabilities]
    #      end
    #
    #      def sheet_body
    #        assets, liabilities = *%w[Assets Liabilities].map { |acct| monthly_totals acct, accrue_before_begin: true }
    #
    #        months_through(starting_at, ending_at).map do |month|
    #          [month.strftime('%m-%y'), assets[month], liabilities[month]]
    #        end
    #      end
    #    end
    #
    # This WealthGrowthGrid, depending on your data, will output a series of grids in your build directory, such as the
    # following:
    # -  build/grids/2018-wealth-growth.csv
    # -  build/grids/2019-wealth-growth.csv
    # -  build/grids/2020-wealth-growth.csv
    # -  build/grids/2021-wealth-growth.csv
    # -  build/grids/2022-wealth-growth.csv
    # -  build/grids/2023-wealth-growth.csv
    #
    # And, inside each of this files, will be a csv similar to:
    #   Date,Assets,Liabilities
    #   01-23,89418.01,-4357.45
    #   02-23,89708.53,-3731.10
    #   03-23,89899.81,-3150.35
    #   04-23,89991.36,-2616.21
    #   05-23,89982.94,-2129.60
    #   06-23,89874.60,-1691.37
    #   07-23,89666.59,-1302.28
    #   08-23,89359.43,-963.00
    #   09-23,88953.92,-674.13
    #   10-23,88451.01,-436.16
    #
    # @attr_reader [Date] starting_at The first day in this instance of the grid
    # @attr_reader [Date] ending_at The last day in this instance of the grid
    # @attr_reader [Integer] year The year segmentation, for an instance of this Grid. This value is pulled from the
    #                             year of :ending_at.
    class Grid
      include RRA::Application::DescendantRegistry
      include RRA::Pta::AvailabilityHelper
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

      # Create a Grid, given the following date segment
      # @param [Date] starting_at See {RRA::Base::Grid#starting_at}.
      # @param [Date] ending_at See {RRA::Base::Grid#ending_at}.
      def initialize(starting_at, ending_at)
        # NOTE: It seems that with monthly queries, the ending date works a bit
        # differently. It's not necessariy to add one to the day here. If you do,
        # you get the whole month of January, in the next year added to the output.
        @year = starting_at.year
        @starting_at = starting_at
        @ending_at = ending_at
      end

      # Write the computed grid, to its default build path
      # @return [void]
      def to_file!
        write! self.class.output_path(year), to_table
        nil
      end

      # Return the computed grid, in a parsed form, before it's serialized to a string.
      # @return [Array[Array<String>]] Each row is an array, itself composed of an array of cells.
      def to_table
        [sheet_header] + sheet_body
      end

      private

      # @!visibility public
      # The provided args are passed to {RRA::Pta::AvailabilityHelper#pta}'s '#register. The total amounts returned  by
      # this query are reduced by account, then month. This means that the return value is a Hash, whose keys correspond
      # to each of the accounts that were encounted. The values for each of those keys, is itself a Hash indexed by
      # month, whose value is the total amount returned, for that month.
      #
      # In addition to the options supported by pta.register, the following options are supported:
      # - *accrue_before_begin* [Boolean] - This flag will create a pta-adapter independent query, to accrue balances
      #   before the start date of the returned set. This is useful if you want to (say) output the current year's
      #   total's, but, you want to start with the ending balance of the prior year, as opposed to '0'.
      # - *initial* [Hash] - defaults to ({}). This is the value we begin to map values from. Typically we want to
      #   start that process from nil, this allows us to decorate the starting point.
      # - *in_code* [String] - defaults to ('$') . This value, expected to be a commodity code, is ultimately passed
      #   to {RRA::Pta::RegisterPosting#total_in}
      # @param [Array<Object>] args See {RRA::Pta::HLedger#register}, {RRA::Pta::Ledger#register} for details
      # @return [Hash<String,Hash<Date,RRA::Journal::Commodity>>] all totals, indexed by month. Months are indexed by
      #                                                          account.
      def monthly_totals_by_account(*args)
        reduce_monthly_by_account(*args, :total_in)
      end

      # @!visibility public
      # The provided args are passed to {RRA::Pta::AvailabilityHelper#pta}'s #register. The amounts returned  by this
      # query are reduced by account, then month. This means that the return value is a Hash, whose keys correspond to
      # each of the accounts that were encounted. The values for each of those keys, is itself a Hash indexed by month,
      # whose value is the amount amount returned, for that month.
      #
      # In addition to the options supported by pta.register, the following options are supported:
      # - *accrue_before_begin* [Boolean] - This flag will create a pta-adapter independent query, to accrue balances
      #   before the start date of the returned set. This is useful if you want to (say) output the current year's
      #   amount's, but, you want to start with the ending balance of the prior year, as opposed to '0'.
      # - *initial* [Hash] - defaults to ({}). This is the value we begin to map values from. Typically we want to
      #   start that process from nil, this allows us to decorate the starting point.
      # - *in_code* [String] - defaults to ('$') . This value, expected to be a commodity code, is ultimately passed
      #   to {RRA::Pta::RegisterPosting#amount_in}
      # @param [Array<Object>] args See {RRA::Pta::HLedger#register}, {RRA::Pta::Ledger#register} for details
      # @return [Hash<String,Hash<Date,RRA::Journal::Commodity>>] all amounts, indexed by month. Months are indexed by
      #                                                          account.
      def monthly_amounts_by_account(*args)
        reduce_monthly_by_account(*args, :amount_in)
      end

      # @!visibility public
      # The provided args are passed to {RRA::Pta::AvailabilityHelper#pta}'s #register. The total amounts returned  by
      # this query are reduced by month. This means that the return value is a Hash, indexed by month (in the form of a
      # Date class) whose value is itself a Commodity, which indicates the total for that month.
      #
      # In addition to the options supported by pta.register, the following options are supported:
      # - *accrue_before_begin* [Boolean] - This flag will create a pta-adapter independent query, to accrue balances
      #   before the start date of the returned set. This is useful if you want to (say) output the current year's
      #   amount's, but, you want to start with the ending balance of the prior year, as opposed to '0'.
      # - *initial* [Hash] - defaults to ({}). This is the value we begin to map values from. Typically we want to
      #   start that process from nil, this allows us to decorate the starting point.
      # - *in_code* [String] - defaults to ('$') . This value, expected to be a commodity code, is ultimately passed
      #   to {RRA::Pta::RegisterPosting#total_in}
      # @param [Array<Object>] args See {RRA::Pta::HLedger#register}, {RRA::Pta::Ledger#register} for details
      # @return [Hash<Date,RRA::Journal::Commodity>] all amounts, indexed by month. Months are indexed by
      #                                                          account.
      def monthly_totals(*args)
        reduce_monthly(*args, :total_in)
      end

      # @!visibility public
      # The provided args are passed to {RRA::Pta::AvailabilityHelper#pta}'s #register. The amounts returned  by this
      # query are reduced by month. This means that the return value is a Hash, indexed by month (in the form of a Date
      # class) whose value is itself a Commodity, which indicates the amount for that month.
      #
      # In addition to the options supported by pta.register, the following options are supported:
      # - *accrue_before_begin* [Boolean] - This flag will create a pta-adapter independent query, to accrue balances
      #   before the start date of the returned set. This is useful if you want to (say) output the current year's
      #   amount's, but, you want to start with the ending balance of the prior year, as opposed to '0'.
      # - *initial* [Hash] - defaults to ({}). This is the value we begin to map values from. Typically we want to
      #   start that process from nil, this allows us to decorate the starting point.
      # - *in_code* [String] - defaults to ('$') . This value, expected to be a commodity code, is ultimately passed
      #   to {RRA::Pta::RegisterPosting#amount_in}
      # @param [Array<Object>] args See {RRA::Pta::HLedger#register}, {RRA::Pta::Ledger#register} for details
      # @return [Hash<Date,RRA::Journal::Commodity>] all amounts, indexed by month. Months are indexed by
      #                                                          account.
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
                      # TODO: I don't think I need this file: here
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

        pta.register(*args, opts).transactions.inject(initial) do |ret, tx|
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

      # @attr_reader [String] name The name of this grid. Typically, this would be an underscorized version of the class
      #                            name, without the _grid suffix. This is used to compose the rake task names for each
      #                            instance of this class.
      # @attr_reader [String] description A description of this grid, for use in a rake task description.
      # @attr_reader [String] output_path_template A string template, for use in building output files. A single '%s'
      #                                            formatter is expected, which, will be substituted with the year of
      #                                            a segment or the string 'all'.
      class << self
        include RRA::Utilities
        include RRA::Pta::AvailabilityHelper

        attr_reader :name, :description, :output_path_template

        # This helper method is provided for child classes, to easily establish a definition of this grid, that
        # can be used to produce it's instances, and their resulting output.
        # @param [String] name See {RRA::Base::Grid.name}.
        # @param [String] description See {RRA::Base::Grid.description}.
        # @param [String] status_name_template A template to use, when composing the build status. A single '%s'
        #                                      formatter is expected, which, will be substituted with the year
        #                                      of a segment or the string 'all'.
        # @param [String] options what options to configure this registry with
        # @option options [String] :output_path_template See {RRA::Base::Grid.output_path_template}.
        # @return [void]
        def grid(name, description, status_name_template, options = {})
          @name = name
          @description = description
          @status_name_template = status_name_template
          @output_path_template = options[:output_path_template]
        end

        # This method returns an array of paths, to the files it produces it's output from. This is used by rake
        # to establish the freshness of our output.  We assume that output is deterministic, and based on these
        # inputs.
        # @return [Array<String>] an array of relative paths, to our inputs.
        def dependency_paths
          # NOTE: This is only used right now, in the plot task. So, the cache is fine.
          # But, if we start using this before the journals are built, we're going to
          # need to clear this cache, thereafter. So, maybe we want to take a parameter
          # here, or figure something out then, to prevent problems.
          @dependency_paths ||= pta.files(file: RRA.app.config.project_journal_path)
        end

        # Whether this grid's outputs are fresh. This is determined, by examing the mtime's of our #dependency_paths.
        # @return [TrueClass, FalseClass] true, if we're fresh, false if we're stale.
        def uptodate?(year)
          FileUtils.uptodate? output_path(year), dependency_paths
        end

        # Given a year, compute the output path for an instance of this grid
        # @param [String,Integer] year The year to which this output is specific. Or, alternatively 'all'.
        # @return [String] relative path to an output file
        def output_path(year)
          raise StandardError, 'Missing output_path_template' unless output_path_template

          [RRA.app.config.build_path('grids'), '/', output_path_template % year, '.csv'].join
        end

        # Given a year, compute the status label for an instance of this grid
        # @param [String,Integer] year The year to which this status is specific. Or, alternatively 'all'.
        # @return [String] A friendly label, constructed from the :status_name_template
        def status_name(year)
          @status_name_template % year
        end
      end

      # This module can be included into classes descending from RRA::Base::Grid, in order to add support for multiple
      # sheets, per year. These sheets can be declared using the provided 'has_sheets' class method, like so:
      #   has_sheets('cashflow') { %w(personal business) }
      # This declaration will ensure the creation of "#\\{year}-cashflow-business.csv" and
      # "#\\{year}-cashflow-personal.csv" grids, in the project's build/grids output. This is achieved by providing the
      # sheet name as a parameter to your #sheet_header, and #sheet_body methods. (see the below example)
      #
      # = Example
      # Here's a simple example of a grid that's segmented both by year, as well as by "property". The property an
      # expense correlates with, is determined by the value of it's property tag (should one exist).
      # This grid will build a separate grid for every property that we've tagged expenses for, with the expenses for
      # that tag, separated by year.
      #   class PropertyExpensesGrid < RRA::Base::Grid
      #     include HasMultipleSheets
      #
      #     grid 'expenses_by_property', 'Generate Property Expense Grids', 'Property Expenses by month (%s)'
      #
      #     has_sheets('property-expenses') { |year| pta.tags 'property', values: true, begin: year, end: year + 1 }
      #
      #     def sheet_header(property)
      #       ['Date'] + sheet_series(property)
      #     end
      #
      #     def sheet_body(property)
      #       months = property_expenses(property).values.map(&:keys).flatten.uniq.sort
      #
      #       months_through_dates(months.first, months.last).map do |month|
      #         [month.strftime('%m-%y')] + sheet_series(property).map { |col| property_expenses(property)[col][month] }
      #       end
      #     end
      #
      #     private
      #
      #     def sheet_series(property)
      #       property_expenses(property).keys.sort
      #     end
      #
      #     def property_expenses(property)
      #       @property_expenses ||= {}
      #       @property_expenses[property] ||= monthly_amounts_by_account(
      #         ledger_args: [format('%%property=%s', property), 'and', 'Expense'],
      #         hledger_args: [format('tag:property=%s', property), 'Expense']
      #       )
      #     end
      #   end
      #
      # This PropertyExpensesGrid, depending on your data, will output a series of grids in your build directory, such
      # as the following:
      # -  build/grids/2018-property-expenses-181_yurakucho.csv
      # -  build/grids/2018-property-expenses-101_0021tokyo.csv
      # -  build/grids/2019-property-expenses-181_yurakucho.csv
      # -  build/grids/2019-property-expenses-101_0021tokyo.csv
      # -  build/grids/2020-property-expenses-181_yurakucho.csv
      # -  build/grids/2020-property-expenses-101_0021tokyo.csv
      # -  build/grids/2021-property-expenses-181_yurakucho.csv
      # -  build/grids/2021-property-expenses-101_0021tokyo.csv
      # -  build/grids/2022-property-expenses-181_yurakucho.csv
      # -  build/grids/2022-property-expenses-101_0021tokyo.csv
      # -  build/grids/2023-property-expenses-181_yurakucho.csv
      # -  build/grids/2023-property-expenses-101_0021tokyo.csv
      #
      # And, inside each of this files, will be a csv similar to:
      #   Date,Business:Expenses:Banking:Interest:181Yurakucho,Business:Expenses:Home:Improvement:181Yurakucho[...]
      #   01-23,123.45,678.90,123.45,678.90,123.45,678.90,123.45,678.90,123.45
      #   02-23,123.45,678.90,123.45,678.90,123.45,678.90,123.45,678.90,123.45
      #   03-23,123.45,678.90,123.45,678.90,123.45,678.90,123.45,678.90,123.45
      #   04-23,123.45,678.90,123.45,678.90,123.45,678.90,123.45,678.90,123.45
      #   05-23,123.45,678.90,123.45,678.90,123.45,678.90,123.45,678.90,123.45
      #   06-23,123.45,678.90,123.45,678.90,123.45,678.90,123.45,678.90,123.45
      #   07-23,123.45,678.90,123.45,678.90,123.45,678.90,123.45,678.90,123.45
      #   07-23,123.45,678.90,123.45,678.90,123.45,678.90,123.45,678.90,123.45
      #   08-23,123.45,678.90,123.45,678.90,123.45,678.90,123.45,678.90,123.45
      #   09-23,123.45,678.90,123.45,678.90,123.45,678.90,123.45,678.90,123.45
      #   10-23,123.45,678.90,123.45,678.90,123.45,678.90,123.45,678.90,123.45
      #   11-23,123.45,678.90,123.45,678.90,123.45,678.90,123.45,678.90,123.45
      #   12-23,123.45,678.90,123.45,678.90,123.45,678.90,123.45,678.90,123.45
      module HasMultipleSheets
        # Return the computed grid, in a parsed form, before it's serialized to a string.
        # @return [Array[Array<String>]] Each row is an array, itself composed of an array of cells.
        def to_table(sheet)
          [sheet_header(sheet)] + sheet_body(sheet)
        end

        # Write the computed grid, to its default build path
        # @return [void]
        def to_file!
          self.class.sheets(year).each do |sheet|
            write! self.class.output_path(year, sheet.to_s.downcase), to_table(sheet)
          end
          nil
        end

        # see (RRA::Base::Grid::HasMultipleSheets.sheets)
        def sheets(year)
          self.class.sheets year
        end

        # @!visibility private
        def self.included(klass)
          klass.extend ClassMethods
        end

        # This module contains the Class methods, that are automatically included,
        # at the time RRA::Base::Grid::HasMultipleSheets is included into a class.
        module ClassMethods
          # Define what additional sheets, this Grid will handle.
          # @param [String] sheet_output_prefix This is used in constructing the output file, and is expected to be
          #                                     a friendly name, describing the container, under which our multiple
          #                                     sheets exist.
          # @yield [year] Return the sheets, that are available in the given year
          # @yieldparam [Integer] year The year being queried.
          # @yieldreturn [Array<String>] The sheets (aka grids) that we can generate for this year
          # @return [void]
          def has_sheets(sheet_output_prefix, &block) # rubocop:disable Naming/PredicateName
            @has_sheets = block
            @sheet_output_prefix = sheet_output_prefix
          end

          # Returns the sheets that are available for the given year. This is calculated using the block provided in
          # #has_sheets
          # @param [Integer] year The year being queried.
          # @return [Array<String>] What sheets (aka grids) are available this year
          def sheets(year)
            @sheets ||= {}
            @sheets[year] ||= @has_sheets.call year
          end

          # Returns the sheet_output_prefix, that was set in #has_sheets
          # @return [String] The label for our multiple sheet taxonomy
          def sheet_output_prefix
            @sheet_output_prefix
          end

          # @!visibility private
          def output_path(year, sheet)
            format '%<path>s/%<year>s-%<prefix>s-%<sheet>s.csv',
                   path: RRA.app.config.build_path('grids'),
                   year: year,
                   prefix: sheet_output_prefix,
                   sheet: sheet.to_s.downcase
          end

          # Whether this grid's outputs are fresh. This is determined, by examing the mtime's of our #dependency_paths.
          # @return [TrueClass, FalseClass] true, if we're fresh, false if we're stale.
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
