# frozen_string_literal: true

require 'csv'

module RRA
  module Utilities
    # This class provides a number of utility functions to query, and merge, grids
    # that have been built. The primary purpose of these tools, is to decrease
    # the overhead that would otherwise exist, if we were to operate directly on
    # the pta output, every time we referenced this data. As well as to maintain
    # auditability for this data, in the project build.
    # @attr_reader [Array<String>] headers The first row of a grid, without the keystone included
    # @attr_reader [Hash<String,Hash<String,Object>>] data A hash whose key is the series name, whose value is a hash of
    #                                                      headername to value pairs
    # @attr_reader [String] keystone The cell in the upper-left of the grid. Often this cell is used as a superordinate
    #                                label for the series below it.
    class GridQuery
      # NOTE: I'm not exactly sure what this class wants to be just yet...
      # Let's see if we end up using it for graphing... It might just be a 'Spreadsheet'
      # and we may want/need to move the summary columns into here
      attr_reader :headers, :data, :keystone

      # Setup a GridQuery
      # @param [Array<String>] from_files An array of paths, to grid files
      # @param [Hash] options Additional options
      # @option options [String] keystone see {RRA::Utilities::GridQuery#keystone}
      # @option options [Proc] store_cell  This proc is provided one parameter, a data cell. The return value of this
      #                                    proc is then stored in :data, in lieu of the parameter.
      # @option options [Proc] select_columns This proc is provided two parameters, a header (String), and the cells
      #                                       underneath it in the grid (Array<Object>). If this proc returns true,
      #                                       that column is stored in :data. If this proc returns false, that column
      #                                       is not retained in this query.
      # @option options [Proc] select_rows This proc is provided two parameters, a series_name (String), and the cells
      #                                    to the right of it in the grid (Array<Object>). If this proc returns true,
      #                                    that column is stored in :data. If this proc returns false, that column
      #                                    is not retained in this query.
      def initialize(from_files, options = {})
        @headers = []
        @data = {}

        from_files.each do |file|
          csv = CSV.open file, 'r', headers: true
          rows = csv.read
          headers = csv.headers

          # We assume the first column of the row, is the series name
          @keystone = headers.shift

          if options[:select_columns]
            selected_headers = headers.select do |header|
              options[:select_columns].call(header, rows.map { |row| row[header] })
            end
          end
          selected_headers ||= headers

          add_columns selected_headers

          rows.each do |row|
            series_data = row.to_h
            series_name = series_data.delete @keystone
            if options.key? :store_cell
              series_data.each do |col, cell|
                next unless !options.key?(:select_columns) || selected_headers.include?(col)

                series_data[col] = options[:store_cell].call cell
              end
            end

            if !options.key?(:select_rows) || options[:select_rows].call(series_name, series_data)
              add_data series_name, series_data
            end
          end
        end

        # This needs to be assigned after we've processed the csv's
        @keystone = options[:keystone] if options.key? :keystone
      end

      # Returns the results of a query.
      # @param [Hash] opts Additional options
      # @option opts [Proc] sort_cols_by Columns are sorted by the value returned by this proc. This proc is provided
      #                                  the grid :headers, and this proc is handled according to the rules of
      #                                  Enumerable#sort_by.
      # @option opts [Proc] sort_rows_by Rows are sorted by the value returned by this proc. This proc is provided
      #                                  each row in this grid, with the series_name of the row at position zero.
      #                                  This proc is handled according to the rules of Enumerable#sort_by.
      # @option opts [Integer] truncate_columns Restrict the total number of columns to a maximum this number
      # @option opts [Integer] truncate_rows Restrict the total number of rows to a maximum this number
      # @option opts [String] truncate_remainder_row If the columns are truncated, the 'chopped' columns are summed into
      #                                              'the last column'. The value of this option, is used as  the label
      #                                              for that column. Candidly... this feature makes a lot of
      #                                              assumptions, and probably needs a bit more refinement.
      # @option opts [TrueClass,FalseClass] switch_rows_columns Rotates the grid, so that series labels and headers are
      #                                     swapped. All data is preserved under/adjacent to the same series label and
      #                                     header, in the returned grid. Google offers this option in its GUI, but
      #                                     doesn't seem to support it via the API. So, we can just do that ourselves
      #                                     here.
      # @return [Array<Array<Object>>] A grid of cells, composed of the provided grids, and transformed by the given
      #                                parameters.
      def to_grid(opts = {})
        # First we'll collect the header row, possibly sorted :
        if opts[:sort_cols_by]
          # We collect the data under the column, and feed that into sort_cols_by
          grid_columns = headers.map do |col|
            [col] + data.map { |_, values| values[col] }
          end.sort_by(&opts[:sort_cols_by]).map(&:first)
        end
        grid_columns ||= headers

        # Then we collect the non-header rows:
        grid = data.map { |series, values| [series] + grid_columns.map { |col| values[col] } }

        # Sort those rows, if necessesary:
        grid.sort_by!(&opts[:sort_rows_by]) if opts[:sort_rows_by]

        # Affix the header row to the top of the grid. Now it's assembled.
        grid.unshift [keystone] + grid_columns

        # Do we Truncate Rows?
        if opts[:truncate_rows] && grid.length > opts[:truncate_rows]
          # We can only have about 26 columns on Google. And, since we're (sometimes)
          # transposing rows to columns, we have to truncate the rows.

          # NOTE: The 1 is for the truncate_remainder_row, the 'overflow' column
          chop_length = grid.length - opts[:truncate_rows]

          if chop_length.positive?
            chopped_rows = grid.pop chop_length
            truncate_row = chopped_rows.inject([]) do |sum, row|
              # Starting at the second cell (the first is the series name) merge
              # the contents of the current row, into the collection cell.
              row[1...].each_with_index.map do |cell, i|
                # This rigamarole is mostly to help prevent type issues...
                if cell
                  sum[i] ? sum[i] + cell : cell
                else
                  sum[i]
                end
              end
            end

            grid << ([(opts[:truncate_remainder_row]) || 'Other'] + truncate_row)
          end
        end

        # Do we Truncate Columns?
        if opts[:truncate_columns] && grid[0].length > opts[:truncate_columns]
          # Go through each row, pop off the excess cells, and sum them onto the end
          grid.each_with_index do |row, i|
            # The plus one is to make room for the 'Other' column
            chop_length = row.length - opts[:truncate_columns] + 1

            chopped_cols = row.pop chop_length
            truncate_cell = if i.zero?
                              opts[:truncate_remainder_row] || 'Other'
                            else
                              chopped_cols.all?(&:nil?) ? nil : chopped_cols.compact.sum
                            end

            row << truncate_cell
          end
        end

        # Google offers this option in its GUI, but doesn't seem to support it via
        # the API. So, we can just do that ourselves:
        grid = 0.upto(grid[0].length - 1).map { |i| grid.map { |row| row[i] } } if opts[:switch_rows_columns]

        grid
      end

      private

      def add_columns(headers)
        @headers += headers.reject { |header| @headers.include? header }
      end

      # NOTE: that we're assuming value here, is always a commodity. Not sure about
      # that over time.
      def add_data(series_name, colname_to_value)
        @data[series_name] ||= {}

        colname_to_value.each do |colname, value|
          raise StandardError, 'Unimplemented. How to merge?' if @data[series_name].key? colname

          @data[series_name][colname] = value
        end
      end
    end
  end
end
