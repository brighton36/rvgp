# frozen_string_literal: true

require 'csv'
require_relative '../application/descendant_registry'
require_relative '../utilities'

module RVGP
  # This module largely exists as a folder, in which to group Parent classes, that are used throughout the project.
  # There's nothing else interesting happening here in this module, other than its use as as namespace.
  module Base
    # This is the base class implementation, for your application-defined grids. The base class works like a grid
    # builder, which, each instance of inheriting grids, representing a single output file.
    #
    # The goal of a grid instance, is to compute csv files, in the project's "build/grids" directory.
    # Sometimes, these grids will simply be an assemblage of pta queries. Other times, these grids won't
    # involve any pta queries at all, and may instead contain projections and statistics computed elsewhere.
    #
    # Users are expected to inherit from this class, in their grid bulding implementations, inside ruby classes defined
    # in your project's app/grids directory. This class offers helpers for working with pta_adapters (particularly for
    # use with annual by-the-month output).  But, you can parameterize anything you'd like, for the purpose of building
    # your grids.
    #
    # A key method in your Grid implement is the {RVGP::Base::Grid.builds} method, which declares the label formatting,
    # and which grids will be produced by the class being defined. See this method (and the example below) for details.
    #
    # The function and purpose of grids, in your project, is as follows:
    # - Store a state of our data in the project's build, and thus its git history.
    # - Provide the data used by a subsequent {RVGP::Plot}, {RVGP::Utilities::GridQuery}, or another program outside
    #   rvgp.
    #
    # ## Example
    # Perhaps the easiest way to understand what this class does, is to look at one of the sample grids produced by
    # the new_project command. Here's the contents of an app/grids/wealth_growth_grid.rb, that you can use in your
    # projects:
    #    class WealthGrowthGrid < RVGP::Base::Grid
    #      builds '%<year>s-wealth-growth', grids: parameters_per_year
    #
    #      def header
    #        %w[Date Assets Liabilities]
    #      end
    #
    #      def body
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
    # ```
    # Date,Assets,Liabilities
    # 01-23,89418.01,-4357.45
    # 02-23,89708.53,-3731.10
    # 03-23,89899.81,-3150.35
    # 04-23,89991.36,-2616.21
    # 05-23,89982.94,-2129.60
    # 06-23,89874.60,-1691.37
    # 07-23,89666.59,-1302.28
    # 08-23,89359.43,-963.00
    # 09-23,88953.92,-674.13
    # 10-23,88451.01,-436.16
    # ```
    # @attr_reader [Array<Hash>] parameters The parameters for this grid instance
    class Grid
      include RVGP::Application::DescendantRegistry
      include RVGP::Pta::AvailabilityHelper
      include RVGP::Utilities

      register_descendants RVGP,
                           :grids,
                           accessors: {
                             task_names: ->(registry) { registry.classes.map(&:task_names).flatten },
                             instances: lambda do |registry|
                               # This is just a time saver really, for an empty build...
                               return [] if RVGP.app.journals_empty?

                               registry.classes.map do |klass|
                                 klass.grids.map { |parameters| klass.new(parameters) }
                               end.flatten
                             end
                           }

      attr_reader :parameters

      def initialize(parameters = {})
        @parameters = parameters
      end

      # Write the computed grid, to its default build path
      # @return [void]
      def to_file!
        table = to_table
        write! output_path, table unless table.compact.empty?
        nil
      end

      # If the grid was provided a :year parameter, returns the first date of the year.
      # @return [Date]
      def starting_at
        # NOTE: We may want to group the :year helpers, and their downstream methods, into their own module.
        @starting_at ||= Date.new parameters[:year], 1, 1 if parameters.key? :year
      end

      # If the grid was provided a :year parameter, returns either the last date of the year, or the
      # {RVGP::Application::Config.grid_ending_at}, whichever is newer.
      # @return [Date]
      def ending_at
        # NOTE: It seems that with monthly queries, the ending date works a bit
        # differently. It's not necessariy to add one to the day here. If you do,
        # you get the whole month of January, in the next year added to the output.
        @ending_at ||= if parameters.key?(:year) && parameters[:year] == RVGP.app.config.grid_ending_at.year
                         RVGP.app.config.grid_ending_at
                       else
                         Date.new parameters[:year], 12, 31
                       end
      end

      # A descriptive name for this grid, given it's parameters. This uses the {Grid.label_fmt} to compose
      # @return [String]
      def label
        format(self.class.label_fmt, @parameters).downcase
      end

      alias status_name label

      # Whether this grid's outputs are fresh. This is determined, by examing the mtime's of our #dependency_paths.
      # @return [TrueClass, FalseClass] true, if we're fresh, false if we're stale.
      def uptodate?
        FileUtils.uptodate? output_path, self.class.dependency_paths
      end

      # The output path for this Grid instance
      def output_path
        format '%<path>s/%<label>s.csv',
               path: RVGP.app.config.build_path('grids'),
               label: label
      end

      # Return the computed grid, in a parsed form, before it's serialized to a string.
      # @return [Array[Array<String>]] Each row is an array, itself composed of an array of cells.
      def to_table
        [header] + body
      end

      private

      # @!visibility public
      # The provided args are passed to {RVGP::Pta::AvailabilityHelper#pta}'s '#register. The total amounts returned  by
      # this query are reduced by account, then month. This means that the return value is a Hash, whose keys correspond
      # to each of the accounts that were encounted. The values for each of those keys, is itself a Hash indexed by
      # month, whose value is the total amount returned, for that month.
      #
      # In addition to the options supported by pta.register, the following options are supported:
      # - **accrue_before_begin** [Boolean] - This flag will create a pta-adapter independent query, to accrue balances
      #   before the start date of the returned set. This is useful if you want to (say) output the current year's
      #   total's, but, you want to start with the ending balance of the prior year, as opposed to '0'.
      # - **initial** [Hash] - defaults to ({}). This is the value we begin to map values from. Typically we want to
      #   start that process from nil, this allows us to decorate the starting point.
      # - **in_code** [String] - defaults to ('$') . This value, expected to be a commodity code, is ultimately passed
      #   to {RVGP::Pta::RegisterPosting#total_in}
      # @param [Array<Object>] args See {RVGP::Pta::HLedger#register}, {RVGP::Pta::Ledger#register} for details
      # @return [Hash<String,Hash<Date,RVGP::Journal::Commodity>>] all totals, indexed by month. Months are indexed by
      #                                                          account.
      def monthly_totals_by_account(*args)
        reduce_monthly_by_account(*args, :total_in)
      end

      # @!visibility public
      # The provided args are passed to {RVGP::Pta::AvailabilityHelper#pta}'s #register. The amounts returned  by this
      # query are reduced by account, then month. This means that the return value is a Hash, whose keys correspond to
      # each of the accounts that were encounted. The values for each of those keys, is itself a Hash indexed by month,
      # whose value is the amount amount returned, for that month.
      #
      # In addition to the options supported by pta.register, the following options are supported:
      # - **accrue_before_begin** [Boolean] - This flag will create a pta-adapter independent query, to accrue balances
      #   before the start date of the returned set. This is useful if you want to (say) output the current year's
      #   amount's, but, you want to start with the ending balance of the prior year, as opposed to '0'.
      # - **initial** [Hash] - defaults to ({}). This is the value we begin to map values from. Typically we want to
      #   start that process from nil, this allows us to decorate the starting point.
      # - **in_code** [String] - defaults to ('$') . This value, expected to be a commodity code, is ultimately passed
      #   to {RVGP::Pta::RegisterPosting#amount_in}
      # @param [Array<Object>] args See {RVGP::Pta::HLedger#register}, {RVGP::Pta::Ledger#register} for details
      # @return [Hash<String,Hash<Date,RVGP::Journal::Commodity>>] all amounts, indexed by month. Months are indexed by
      #                                                          account.
      def monthly_amounts_by_account(*args)
        reduce_monthly_by_account(*args, :amount_in)
      end

      # @!visibility public
      # The provided args are passed to {RVGP::Pta::AvailabilityHelper#pta}'s #register. The total amounts returned  by
      # this query are reduced by month. This means that the return value is a Hash, indexed by month (in the form of a
      # Date class) whose value is itself a Commodity, which indicates the total for that month.
      #
      # In addition to the options supported by pta.register, the following options are supported:
      # - **accrue_before_begin** [Boolean] - This flag will create a pta-adapter independent query, to accrue balances
      #   before the start date of the returned set. This is useful if you want to (say) output the current year's
      #   amount's, but, you want to start with the ending balance of the prior year, as opposed to '0'.
      # - **initial** [Hash] - defaults to ({}). This is the value we begin to map values from. Typically we want to
      #   start that process from nil, this allows us to decorate the starting point.
      # - **in_code** [String] - defaults to ('$') . This value, expected to be a commodity code, is ultimately passed
      #   to {RVGP::Pta::RegisterPosting#total_in}
      # @param [Array<Object>] args See {RVGP::Pta::HLedger#register}, {RVGP::Pta::Ledger#register} for details
      # @return [Hash<Date,RVGP::Journal::Commodity>] all amounts, indexed by month. Months are indexed by
      #                                                          account.
      def monthly_totals(*args)
        reduce_monthly(*args, :total_in)
      end

      # @!visibility public
      # The provided args are passed to {RVGP::Pta::AvailabilityHelper#pta}'s #register. The amounts returned  by this
      # query are reduced by month. This means that the return value is a Hash, indexed by month (in the form of a Date
      # class) whose value is itself a Commodity, which indicates the amount for that month.
      #
      # In addition to the options supported by pta.register, the following options are supported:
      # - **accrue_before_begin** [Boolean] - This flag will create a pta-adapter independent query, to accrue balances
      #   before the start date of the returned set. This is useful if you want to (say) output the current year's
      #   amount's, but, you want to start with the ending balance of the prior year, as opposed to '0'.
      # - **initial** [Hash] - defaults to ({}). This is the value we begin to map values from. Typically we want to
      #   start that process from nil, this allows us to decorate the starting point.
      # - **in_code** [String] - defaults to ('$') . This value, expected to be a commodity code, is ultimately passed
      #   to {RVGP::Pta::RegisterPosting#amount_in}
      # @param [Array<Object>] args See {RVGP::Pta::HLedger#register}, {RVGP::Pta::Ledger#register} for details
      # @return [Hash<Date,RVGP::Journal::Commodity>] all amounts, indexed by month. Months are indexed by
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

        opts.merge!({ pricer: RVGP.app.pricer,
                      monthly: true,
                      empty: false, # This applies to Ledger, and ensures it's results match HLedger's exactly
                      # TODO: I don't think I need this file: here
                      file: RVGP.app.config.project_journal_path })

        opts[:hledger_opts] ||= {}
        opts[:ledger_opts] ||= {}
        opts[:hledger_args] ||= []

        if accrue_before_begin
          opts[:ledger_opts][:display] = format('date>=[%<starting_at>s] and date <=[%<ending_at>s]',
                                                starting_at: starting_at.strftime('%Y-%m-%d'),
                                                ending_at: ending_at.strftime('%Y-%m-%d'))
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

          opts_end = opts.delete(:end) || ending_at
          # TODO: I think we should instead set this from opts[:end]
          opts[:ledger_opts][:end] = (opts[:ledger_opts][:end] || (opts_end + 1)).strftime('%Y-%m-%d')
          opts[:hledger_opts][:end] = (opts[:hledger_opts][:end] || opts_end).strftime('%Y-%m-%d')
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
            csv << row.map { |val| val.is_a?(RVGP::Journal::Commodity) ? val.to_s(no_code: true, precision: 2) : val }
          end
        end
        RVGP::CachedPta.invalidate! path
      end

      # @attr_reader [String] label_fmt A format string, to use in composing a grid label. Typically, this would be an
      #                                underscorized version of the instance name, without the _grid suffix. This is
      #                                applied via format()to the grid parameters to compose the rake task names,
      #                                and file names.
      class << self
        include RVGP::Utilities
        include RVGP::Pta::AvailabilityHelper

        attr_reader :label_fmt

        # This helper method is provided for child classes, to easily establish a definition of this grid, that
        # can be used to produce it's instances, and their resulting output.
        # @param [String] label_fmt See {RVGP::Base::Grid#label_fmt}.
        # @param [Hash] opts The options to configure this palette with
        # @option opts [lambda] :grids The base colors for this plot. Currently, the following base colors
        #                              This method will be used to generate an array of hashes. With, each element in
        #                              that array, representing a grid instance that needs to be built. There are no
        #                              parameters supplied to this method. Each element of the array it returns, will
        #                              be provided to a Grid in its {initialize} method.
        # @return [void]
        def builds(label_fmt, **opts)
          @label_fmt = label_fmt
          @grid_parameters = opts[:grids] if opts.key? :grids
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
          @dependency_paths ||= cached_pta('*.journal').files(file: RVGP.app.config.project_journal_path)
        end

        # The task names, that rake will build, produced by this grid
        # @return [Array<String>] An array of task names, corresponding to the grids this class produces. Defaults to
        #                         'one per year'
        def task_names
          return [] if RVGP.app.journals_empty?

          grids.map { |parameters| ['grid:', (new parameters).label].join }
        end

        # The Grids, which this class will build
        # @return [Array<Hash>] An array of parameters, corresponding to the grids this class produces.
        def grids
          @grid_parameters&.call || [{}]
        end

        # This method is intended for use as a helper, provided to the {RVGP::Base::Grid.builds}'s :grids option.
        # Provided no parameters, this method will return an Array<Hash>, with, each Hash containing a :year, set
        # to one of the years returned by {configured_grid_years}. If a lambda is provided to this method, that
        # lambda will be used to map each of the years, and will be provided with a <Int> year parameter, and
        # will be expected to return a Hash of Grid parameters for the provided year.
        # @return [lambda]
        def parameters_per_year(each_year = nil)
          lambda do
            configured_grid_years.map do |year|
              each_year ? each_year.call(year) : { year: year }
            end.flatten.compact
          end
        end

        # This shortcut method will return the range of years between {RVGP::Application::Config.grid_starting_at} and
        # {RVGP::Application::Config.grid_ending_at} (inclusive).
        # @return [Array<Int>]
        def configured_grid_years
          RVGP.app.config.grid_starting_at.year.upto(RVGP.app.config.grid_ending_at.year)
        end
      end
    end
  end
end
