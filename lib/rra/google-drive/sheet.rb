# frozen_string_literal: true

module RRA
  module GoogleDrive
    # This class represents a csv-like matrix, that is to be sent to google, as a sheet
    # in an exported workbook. There's not much logic here.
    class Sheet
      attr_accessor :title, :options

      MAX_COLUMNS = 26

      def initialize(title, grid, options = {})
        @title = title
        @options = options
        @grid = grid

        # This is a Google constraint:
        if columns.length > MAX_COLUMNS
          raise StandardError, format('Too many columns. Max is %<max>d, provided %<provided>d.',
                                      max: MAX_COLUMNS,
                                      provided: columns.length)
        end
      end

      def columns
        @grid[0]
      end

      def rows
        @grid[1...]
      end
    end
  end
end
