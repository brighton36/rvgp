# frozen_string_literal: true

gem 'tty-table'
require 'tty-table'

module RRA
  class Dashboard
    CELL_PADDING = [0, 1, 0, 1]
    NULL_CELL_TO_TABLE = { value: '⋯', alignment: :center }

    attr_reader :label, :series_column_label, :csv

    def initialize(label, csv, options = {})
      @label, @csv = label, csv
      @pastel = options[:pastel] || Pastel.new
      @series_column_label = options[:series_column_name] || 'Series'

      @columns_ordered_by = options[:columns_ordered_by]
      @series_ordered_by = options[:series_ordered_by]

      @format_data_cell = options[:format_data_cell]
      @format_series_label = options[:format_series_label]
      @summaries = options[:summaries]

      raise StandardError, "One or more summaries are incomplete" unless (
        @summaries.all?{|s| %w(label contents).all?{|k| s.has_key? k.to_sym} } )
    end

    # This returns the widest data value (we're not including the padding) that
    # exists in each column. 
    def column_data_widths
      # Now compute the width of each cell's contents:
      to_a.inject(Array.new) do |ret, row|
        row.collect.with_index do |cell, col_i|
          cell_width = cell.respond_to?(:length) ? cell.length : 0
          (ret[col_i].nil? or ret[col_i] < cell_width) ? cell_width : ret[col_i] 
        end
      end
    end

    # The goal here is to return the full table, without ansi decorators, or
    # to_s output options that will mutate state
    def to_a
      # This is the table in full, without ansi, ordering, or width modifiers. 
      # More or less, this is a plain text representation, in full, of the data

      @to_a ||= [[series_column_label]+sorted_headers]+(
        series_rows.dup.collect!(&self.method(:format_series_row)))+summary_rows
    end

    def to_s(options = {})
      column_widths = (options.has_key? :column_widths) ? 
        options[:column_widths] : nil
      header_row = [series_column_label]+sorted_headers
      footer_rows = summary_rows
      content_rows = series_rows

      ([header_row]+content_rows+footer_rows).each do |row| 
        row.pop row.length-column_widths.length
      end if column_widths

      # Now let's strip the rows we no longer need to show:
      content_rows.select!(&options[:show_row]) if options.has_key? :show_row

      # Sort the content:
      content_rows.sort_by!(&options[:rows_ordered_by]) if (
        options.has_key? :rows_ordered_by)

      # Then format the series and data cells:
      content_rows.collect!(&self.method(:format_series_row))

      prettify '%s Dashboard' % label.to_s, 
        [header_row]+content_rows+footer_rows, 
        column_widths
    end

    private

    def column_count
      series_rows[0].length
    end

    def summary_rows
      series_column = series_rows.collect{|row| row[0]}
      @summary_rows ||= @summaries.collect{|summary|
        format_series_row [summary[:label]]+0.upto(column_count).collect{|i| 
          summary[:contents].call series_column, series_rows.collect{|row| row[i+1]}
        }
      }
    end

    def format_series_row(row)
      series_label, series_data = row[0], row[1..]
      series_label = @format_series_label.call(series_label) if @format_series_label
      series_data.collect!{|cell| @format_data_cell.call(cell)} if @format_data_cell
      [series_label]+series_data
    end


    def sorted_headers
      @sorted_headers ||= @columns_ordered_by ? 
        csv.headers.sort(&@columns_ordered_by) : csv.headers
    end

    def series_rows
      @series_rows ||= csv.data.keys.collect{|series| 
        [series]+sorted_headers.collect{|header| csv.data[series][header]}
      }
    end

    # This handles pretty much all of the presentation code. Given a set of cells, 
    # it outputs the 'pretty' tables in ansi. 
    def prettify(title, rows, out_col_widths)
      separators = [0] # NOTE: 1 is the header row

      rows = rows.each_with_index.collect{|row, i| 
        prettifier = nil

        # Is this a subtotal row?
        if rows.length-i <= @summaries.length
          # This is kind of sloppy, but, it works for now. We assume that there's
          # a final subtotal row, and any other summaries are subtotals. At least
          # for presentation logic. (Where to put the lines and such)
          prettifier = @summaries[@summaries.length-(rows.length- i)][:prettify]
          case rows.length-i
            when @summaries.length
              # This is the first of the summaries
              separators << i-1
            when 1
              # We assume this is the total
              separators << i-1
          end
        end

        if i == 0
          row.each_with_index.collect{|cell, j| 
            {value: @pastel.bold("%s" % cell), alignment: (j == 0) ? :left : :center}
          }
        elsif prettifier
          prettifier.call(row)
        else
          row.each_with_index.collect{|cell, j| 
            if i == 0
              {value: @pastel.bold("%s" % cell), alignment: (j == 0) ? :left : :center}
            else
              if j == 0
                @pastel.blue(cell.to_s) 
              else
                cell || NULL_CELL_TO_TABLE
              end
            end
          } 
        end
      }

      # Insert separators, bottom to top:
      table_out = TTY::Table.new(rows).render(:unicode) {|renderer|
        renderer.alignments = [:left]+(2.upto(rows.length).to_a).collect{:right}
        renderer.padding = CELL_PADDING
        renderer.border do
          top_left '├'
          top_right '┤'
        end
        renderer.border.separator = separators
        renderer.column_widths = out_col_widths if out_col_widths
      }

      table_width = table_out.lines[0].length
      title_space = (table_width-3-2-title.length).to_f/2

      [
        # Headcap:
        ['┌','─'*(table_width-3),'┐'].join,
        ['│',
        @pastel.blue('▒')*title_space.ceil,' ',
        @pastel.blue(title),
        ' ', @pastel.blue('▒')*title_space.floor,
        '│'].join,
        # Content:
        table_out
      ].join("\n")
    end

    def self.table_width_given_column_widths(column_widths)
      accumulated_width = 1 # One is the width of the left-most border '|'
      accumulated_width += column_widths.collect{|w|
        [ Dashboard::CELL_PADDING[1], w, Dashboard::CELL_PADDING[3],
        1 # This one is the cell's right-most border '|'
        ] }.flatten.sum
    end
  end
end
