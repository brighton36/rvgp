# frozen_string_literal: true

gem 'tty-table'
require 'tty-table'

module RVGP
  # This class implements a basic graphical dashboard, for use on ansi terminals.
  # These dashboards resemble tables, with stylized headers and footers.
  # Here's a rough example, of what these dashboards look like:
  # ```
  # ┌────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
  # │▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒ Personal Dashboard ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒│
  # ├────────────────────────────────────────────────────┬─────────────┬─────────────┬─────────────┬─────────────┤
  # │ Account                                            │    01-23    │    02-23    │    03-23    │    04-23    │
  # ├────────────────────────────────────────────────────┼─────────────┼─────────────┼─────────────┼─────────────┤
  # │ Personal:Expenses:Food:Groceries                   │    $ 500.00 │    $ 510.00 │    $ 520.00 │    $ 530.00 │
  # │ Personal:Expenses:Food:Restaurants                 │    $ 250.00 │    $ 260.00 │    $ 270.00 │    $ 280.00 │
  # │ Personal:Expenses:Phone:Service                    │     $ 75.00 │     $ 75.00 │     $ 75.00 │    $  75.00 │
  # │ Personal:Expenses:Transportation:Gas               │    $ 150.00 │    $ 180.00 │    $ 280.00 │    $ 175.00 │
  # ├────────────────────────────────────────────────────┼─────────────┼─────────────┼─────────────┼─────────────┤
  # │ Expenses                                           │  $   975.00 │  $ 1,025.00 │  $ 1,145.00 │  $ 1,060.00 │
  # │ Income                                             │ $ -2,500.00 │ $ -2,500.00 │ $ -2,500.00 │ $ -2,500.00 │
  # ├────────────────────────────────────────────────────┼─────────────┼─────────────┼─────────────┼─────────────┤
  # │ Cash Flow                                          │ $ -1,525.00 │ $ -1,475.00 │ $ -1,355.00 │ $ -1,440.00 │
  # └────────────────────────────────────────────────────┴─────────────┴─────────────┴─────────────┴─────────────┘
  # ```
  #
  # There's a lot of functionality here, but, it's mostly unused at the moment, outside the cashflow command.
  # Ultimately, this is probably going to end up becoming a {RVGP::Grid} viewing tool on the cli.
  # @attr_reader [String] label The label for this dashboard. This is used in the first row, of the output
  # @attr_reader [String] series_column_label The label, describing what our series represents. This is also
  #                                           known as the 'keystone'.
  # @attr_reader [RVGP::Utilities::GridQuery] csv The grid and data that this Dashboard will output
  class Dashboard
    # @!visibility private
    CELL_PADDING = [0, 1, 0, 1].freeze
    # @!visibility private
    NULL_CELL_TO_TABLE = { value: '⋯', alignment: :center }.freeze

    attr_reader :label, :series_column_label, :csv

    # Create a Dashboard, which can thereafter be output to the console via {#to_s}
    # @param [String] label See {Dashboard#label}
    # @param [String] csv See {Dashboard#csv}
    # @param [Hash] options Additional, optional, parameters
    # @option options [String] series_column_label see {Dashboard#series_column_label}
    # @option options [Pastel] pastel (Pastel.new) A Pastel object to use, for coloring and boldfacing
    # @option options [Proc<Array<Object>, Array<Object>>] columns_ordered_by This proc is sent to Enumerable#sort with
    #                                                      two parameters, of type Array. Each of these array's is a
    #                                                      column. Your columns are ordered based on whether -1, 0, or 1
    #                                                      is returned. See Enumerable#sort for details on how this
    #                                                      works.
    # @option options [Proc<Object>] format_data_cell This proc is called, with the contents of each data cell in the
    #                                                 dashboard. Whatever it returns is converted to a string, and
    #                                                 rendered.
    # @option options [Proc<Object>] format_series_label This proc is called, with the contents of each series label in
    #                                                    the dashboard. Whatever it returns is converted to a string,
    #                                                    and rendered.
    # @option options [Array<Hash<Symbol,String>>] summaries An array of Hashes, each of which is expected to contain
    #                                                        :label and :contents parameters. In addition, a :prettify
    #                                                        parameter is also supported. Each of these Hashes are
    #                                                        rendered at the bottom of the table, using the :label and
    #                                                        :contents provided. If :prettify is provided, this
    #                                                        parameter is provided the row, before rendering, so that
    #                                                        ansi formatting is applied to the :contents.
    def initialize(label, csv, options = {})
      @label = label
      @csv = csv
      @pastel = options[:pastel] || Pastel.new
      @series_column_label = options[:series_column_label] || 'Series'

      @columns_ordered_by = options[:columns_ordered_by]

      @format_data_cell = options[:format_data_cell]
      @format_series_label = options[:format_series_label]
      @summaries = options[:summaries]

      unless @summaries.all? { |s| %w[label contents].all? { |k| s.key? k.to_sym } }
        raise StandardError, 'One or more summaries are incomplete'
      end
    end

    # Calculates the width requirements of each column, given the data that is present in that column
    # Note that we're not including the padding in this calculation.
    # @return [Array<Integer>] The widths for each column
    def column_data_widths
      # Now compute the width of each cell's contents:
      to_a.inject([]) do |ret, row|
        row.map.with_index do |cell, col_i|
          cell_width = cell.respond_to?(:length) ? cell.length : 0
          ret[col_i].nil? || ret[col_i] < cell_width ? cell_width : ret[col_i]
        end
      end
    end

    # The goal here is to return the full table, without ansi decorators, and
    # without any to_s output options that will mutate state. The returned object's
    # may or may not be String, depending on whether the :format_series_row was provided to #initialize
    # @return [Array<Array<Object>>] The grid, that this dashboard will render
    def to_a
      # This is the table in full, without ansi, ordering, or width modifiers.
      # More or less, this is a plain text representation, in full, of the data

      @to_a ||= [[series_column_label] + sorted_headers] +
                series_rows.dup.map!(&method(:format_series_row)) + summary_rows
    end

    # Render this Dashboard to a string. Presumably for printing to the console.
    # @param [Hash] options Optional formatting specifiers
    # @option options [Array<Integer>] column_widths Use these widths for our columns, instead of the automatically
    #                                                deduced widths. This parameter eventually makes it's way down to
    #                                                TTY::Table's column_widths parameter.
    # @option options [Proc<Array<Object>>] show_row This proc is called with a row, as its parameter. And, if the Proc
    #                                                returns true, the row is displayed. (And if not, the row is hidden)
    # @option options [Proc<Array<Object>>] rows_ordered_by This proc is sent to Enumerable#sort_by! with a row, as its
    #                                                      parameter. The returned value, will be used as the sort
    #                                                      element thereafter
    # @return [String] Your dashboard. The finished product. Print this to STDOUT
    def to_s(options = {})
      column_widths = options.key?(:column_widths) ? options[:column_widths] : nil
      header_row = [series_column_label] + sorted_headers
      footer_rows = summary_rows
      content_rows = series_rows

      if column_widths
        ([header_row] + content_rows + footer_rows).each { |row| row.pop row.length - column_widths.length }
      end

      # Now let's strip the rows we no longer need to show:
      content_rows.select!(&options[:show_row]) if options.key? :show_row

      # Sort the content:
      content_rows.sort_by!(&options[:rows_ordered_by]) if options.key? :rows_ordered_by

      # Then format the series and data cells:
      content_rows.map!(&method(:format_series_row))

      prettify format('%s Dashboard', label.to_s), [header_row] + content_rows + footer_rows, column_widths
    end

    # This helper is provided with the intention of being used with {RVGP::Dashboard#column_data_widths}.
    # Given the return value of #column_data_widths, this method will return the width of a rendered
    # dashboard onto the console. That means we account for padding and cell separation character(s) in
    # this calculation.
    # @param [Array<Integer>] column_widths The widths of each column in the table whose width you wish to
    # calculate
    # @return [Integer] The width of the table, once rendered
    def self.table_width_given_column_widths(column_widths)
      accumulated_width = 1 # One is the width of the left-most border '|'
      accumulated_width + column_widths.map do |w|
        [Dashboard::CELL_PADDING[1], w, Dashboard::CELL_PADDING[3], 1] # This one is the cell's right-most border '|'
      end.flatten.sum
    end

    private

    def column_count
      series_rows[0].length
    end

    def summary_rows
      series_column = series_rows.map { |row| row[0] }
      @summary_rows ||= @summaries.map do |summary|
        format_series_row([summary[:label]] + 0.upto(column_count).map do |i|
          summary[:contents].call(series_column, series_rows.map { |row| row[i + 1] })
        end.to_a)
      end
    end

    def format_series_row(row)
      series_label = row[0]
      series_data = row[1..]
      series_label = @format_series_label.call(series_label) if @format_series_label
      series_data.map! { |cell| @format_data_cell.call(cell) } if @format_data_cell
      [series_label] + series_data
    end

    def sorted_headers
      @sorted_headers ||= @columns_ordered_by ? csv.headers.sort(&@columns_ordered_by) : csv.headers
    end

    def series_rows
      @series_rows ||= csv.data.keys.map do |series|
        [series] + sorted_headers.map { |header| csv.data[series][header] }
      end
    end

    # This handles pretty much all of the presentation code. Given a set of cells,
    # it outputs the 'pretty' tables in ansi.
    def prettify(title, rows, out_col_widths)
      separators = [0] # NOTE: 1 is the header row

      rows = rows.each_with_index.map do |row, i|
        prettifier = nil

        # Is this a subtotal row?
        if rows.length - i <= @summaries.length
          # This is kind of sloppy, but, it works for now. We assume that there's
          # a final subtotal row, and any other summaries are subtotals. At least
          # for presentation logic. (Where to put the lines and such)
          prettifier = @summaries[@summaries.length - (rows.length - i)][:prettify]

          # This is the first of the summaries, or the total
          separators << (i - 1) if [@summaries.length, 1].include? rows.length - i
        end

        if i.zero?
          row.each_with_index.map { |cell, j| { value: @pastel.bold(cell), alignment: j.zero? ? :left : :center } }
        elsif prettifier
          prettifier.call(row)
        else
          row.each_with_index.map do |cell, j|
            if i.zero?
              { value: @pastel.bold(cell), alignment: j.zero? ? :left : :center }
            elsif j.zero?
              @pastel.blue cell.to_s
            else
              cell || NULL_CELL_TO_TABLE
            end
          end
        end
      end

      # Insert separators, bottom to top:
      table_out = TTY::Table.new(rows).render(:unicode) do |renderer|
        renderer.alignments = [:left] + 2.upto(rows.length).to_a.map { :right }
        renderer.padding = CELL_PADDING
        renderer.border do
          top_left '├'
          top_right '┤'
        end
        renderer.border.separator = separators
        renderer.column_widths = out_col_widths if out_col_widths
      end

      table_width = table_out.lines[0].length
      title_space = (table_width - 3 - 2 - title.length).to_f / 2

      [
        # Headcap:
        ['┌', '─' * (table_width - 3), '┐'].join,
        ['│',
         @pastel.blue('▒') * title_space.ceil, ' ',
         @pastel.blue(title),
         ' ', @pastel.blue('▒') * title_space.floor,
         '│'].join,
        # Content:
        table_out
      ].join("\n")
    end
  end
end
