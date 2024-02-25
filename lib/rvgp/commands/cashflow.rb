# frozen_string_literal: true

require_relative '../utilities/grid_query'
require_relative '../dashboard'

module RRA
  module Commands
    # @!visibility private
    # This class contains the logic necessary to display the 'cashflow' dashboard
    class Cashflow < RRA::Base::Command
      accepts_options OPTION_ALL, OPTION_LIST, [:date, :d, { has_value: 'DATE' }]

      # @!visibility private
      # This class handles the target argument, passed on the cli
      class Target < RRA::Base::Command::Target
        # @!visibility private
        def self.all
          RRA::Commands::Cashflow.grids_by_targetname.keys.map { |s| new s }
        end
      end

      # @!visibility private
      def initialize(*args)
        super(*args)

        options[:date] = Date.strptime options[:date] if options.key? :date

        minimum_width = RRA::Dashboard.table_width_given_column_widths(column_widths[0..1])

        unless TTY::Screen.width > minimum_width
          @errors << I18n.t(
            'commands.cashflow.errors.screen_too_small',
            screen_width: TTY::Screen.width,
            minimum_width: minimum_width
          )
        end
      end

      # @!visibility private
      def execute!
        puts dashboards.map { |dashboard|
          dashboard.to_s(
            column_widths: column_widths[0...show_columns],
            rows_ordered_by: lambda { |row|
              series = row[0]
              data = row[1..]
              # Sort by the series type [Expenses/Income/etc], then by 'consistency',
              # then by total amount
              [series.split(':')[1], data.count(&:nil?), data.compact.sum * -1]
            },
            # Hide rows without any data
            show_row: ->(row) { !row[1..].all?(&:nil?) }
          )
        }.join("\n\n")
      end

      # @!visibility private
      def self.cashflow_grid_files
        Dir.glob RRA.app.config.build_path('grids/*-cashflow-*.csv')
      end

      # @!visibility private
      def self.grids_by_targetname
        @grids_by_targetname ||= cashflow_grid_files.each_with_object({}) do |file, sum|
          unless /([^-]+)\.csv\Z/.match file
            raise StandardError, I18n.t('commands.cashflow.errors.unrecognized_path', file: file)
          end

          tablename = ::Regexp.last_match(1).capitalize

          sum[tablename] ||= []
          sum[tablename] << file

          sum
        end
      end

      private

      def dashboards
        @dashboards ||= targets.map do |target|
          RRA::Dashboard.new(
            target.name,
            RRA::Utilities::GridQuery.new(
              self.class.grids_by_targetname[target.name],
              store_cell: lambda { |cell|
                cell ? RRA::Journal::Commodity.from_symbol_and_amount('$', cell) : cell
              },
              select_columns: lambda { |col, column|
                if options.key?(:date)
                  Date.strptime(col, '%m-%y') <= options[:date]
                else
                  column.any? { |cell| !cell.nil? }
                end
              }
            ),
            { pastel: RRA.pastel,
              series_column_label: I18n.t('commands.cashflow.account'),
              format_data_cell: ->(cell) { cell&.to_s commatize: true, precision: 2 },
              columns_ordered_by: ->(a, b) { [b, a].map { |d| Date.strptime d, '%m-%y' }.reduce :<=> },
              summaries: [
                {
                  label: I18n.t('commands.cashflow.expenses'),
                  prettify: ->(row) { [RRA.pastel.bold(row[0])] + row[1..].map { |s| RRA.pastel.red(s) } },
                  contents: ->(series, data) { sum_column 'Expenses', series, data }
                },
                {
                  label: I18n.t('commands.cashflow.income'),
                  prettify: ->(row) { [RRA.pastel.bold(row[0])] + row[1..].map { |s| RRA.pastel.green(s) } },
                  contents: ->(series, data) { sum_column 'Income', series, data }
                },
                {
                  label: I18n.t('commands.cashflow.cash_flow'),
                  prettify: lambda { |row|
                    [RRA.pastel.bold(row[0])] + row[1..].map do |cell|
                      /\$ *-/.match(cell) ? RRA.pastel.red(cell) : RRA.pastel.green(cell)
                    end
                  },
                  contents: lambda { |series, data|
                    %w[Expenses Income].map { |s| sum_column s, series, data }.sum.invert!
                  }
                }
              ] }
          )
        end
      end

      def column_widths
        # We want every table being displayed, to have the same column widths.
        # probably we can move most of this code into a Dashboard class method. But, no
        # rush on that.
        @column_widths ||= dashboards.map(&:column_data_widths)
                                     .inject([]) do |sum, widths|
                                       widths.map.with_index { |w, i| sum[i].nil? || sum[i] < w ? w : sum[i] }
                                     end
      end

      def show_columns
        return @show_columns if @show_columns

        # Now let's calculate how many columns fit on screen:
        @show_columns = 0
        0.upto(column_widths.length - 1) do |i|
          break if RRA::Dashboard.table_width_given_column_widths(column_widths[0..i]) > TTY::Screen.width

          @show_columns += 1
        end
        @show_columns
      end

      def sum_column(for_series, series, data)
        # NOTE: This for_series determination is a bit 'magic' and specific to our
        # current accounting categorization taxonomy
        0.upto(series.length - 1).map do |i|
          series[i].split(':')[1] == for_series && data[i] ? data[i] : '$0.00'.to_commodity
        end.compact.sum
      end
    end
  end
end
