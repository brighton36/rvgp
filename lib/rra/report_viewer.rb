require 'csv'

module RRA
  # NOTE: I'm not exactly sure what this class wants to be just yet...
  # Let's see if we end up using it for graphing... It might just be a 'Spreadsheet'
  # and we may want/need to move the summary columns into here
  class ReportViewer
    attr_reader :headers, :data, :series_label

    def initialize(from_files, options = {})
      @headers, @data = [], {}

      from_files.each do |file|
        csv = CSV.open file, "r", headers: true
        rows = csv.read
        headers = csv.headers

        # We assume the first column of the row, is the series name
        @series_label = headers.shift

        selected_headers = (options[:select_columns]) ? 
          headers.select{|header| 
            column = rows.collect{|row| row[header]}
            options[:select_columns].call(header, column)
          } : headers

        add_columns selected_headers
        
        rows.each do |row| 
          series_data = row.to_h
          series_name = series_data.delete @series_label
          series_data.each do |col, cell|
            next unless (!options.has_key?(:select_columns) || 
              selected_headers.include?(col) if options[:select_columns])

            series_data[col] = options[:store_cell].call cell
          end if options.has_key? :store_cell

          add_data series_name, series_data if !options.has_key?(:select_rows) or 
            options[:select_rows].call(series_name, series_data)
        end
      end

      # This needs to be assigned after we've processed the csv's
      @series_label = options[:series_label] if options.has_key? :series_label
    end

    def to_grid(opts = {})
      # First we'll collect the header row, possibly sorted :
      grid_columns = (opts[:sort_by_cols]) ?
        # We collect the data under the column, and feed that into sort_by_cols
        headers.collect{|col| 
          [col]+data.collect{|series, values| values[col]} 
        }.sort_by(&opts[:sort_by_cols]).collect(&:first) : 
        headers

      # Then we collect the non-header rows:
      grid = data.collect{ |series, values| 
        [series]+grid_columns.collect{|col| values[col]} }

      # Sort those rows, if necessesary:
      grid.sort_by!(&opts[:sort_by_rows]) if opts[:sort_by_rows]

      # Affix the header row to the top of the grid. Now it's assembled.
      grid.unshift [series_label]+grid_columns
      
      # Do we Truncate Rows?
      if opts[:truncate_rows] and grid.length > opts[:truncate_rows]
        # We can only have about 26 columns on Google. And, since we're (sometimes)
        # transposing rows to columns, we have to truncate the rows.

        # NOTE: The 1 is for the truncate_remainder_row, the 'overflow' column
        chop_length = grid.length-opts[:truncate_rows]

        if chop_length > 0
          chopped_rows = grid.pop chop_length
          truncate_row = chopped_rows.inject([]) { |sum, row|
            # Starting at the second cell (the first is the series name) merge
            # the contents of the current row, into the collection cell.
            row[1...].each_with_index.collect do |cell, i|
              # This rigamarole is mostly to help prevent type issues...
              (cell) ? ( (sum[i]) ? sum[i] + cell : cell ) : sum[i]
            end
          }

          grid << [(opts[:truncate_remainder_row]) || 'Other'] + truncate_row
        end
      end

      # Do we Truncate Columns?
      if opts[:truncate_cols] and grid_columns.length > opts[:truncate_cols]
        # Go through each row, pop off the excess cells, and sum them onto the end
        grid.each_with_index do |row, i|
          # The plus one is to make room for the 'Other' column
          chop_length = row.length-opts[:truncate_cols]+1

          chopped_cols = row.pop chop_length
          truncate_cell = (i == 0) ?
            (opts[:truncate_remainder_row] || 'Other') : 
            (chopped_cols.all?(&:nil?) ? nil : chopped_cols.compact.sum)

          row << truncate_cell
        end
      end

      grid
    end

    private

    def add_columns(headers)
      @headers += headers.reject{|header| @headers.include? header}
    end

    # NOTE that we're assuming value here, is always a commodity. Not sure about 
    # that over time.
    def add_data(series_name, colname_to_value)
      @data[series_name] ||= {}

      colname_to_value.each do |colname, value|
        raise StandardError, 
          "Unimplemented. How to merge?" if @data[series_name].has_key? colname

        @data[series_name][colname] = value
      end
    end
  end
end
