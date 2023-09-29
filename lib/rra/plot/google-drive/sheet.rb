# frozen_string_literal: true

module RRA
  class Plot
    module GoogleDrive
      # This class represents a csv-like matrix, that is to be sent to google, as a sheet
      # in an exported workbook. There's not much logic here.
      # @attr_reader [string] title The title of this sheet
      # @attr_reader [Hash] options The options configured on this sheet
      class Sheet
        attr_accessor :title, :options

        # This is the maximum number of columns that we support, in our sheets. This number is
        # mostly here because Google stipulates this restriction
        MAX_COLUMNS = 26

        # A sheet, and its options.
        # @param [String] title The title of this sheet
        # @param [Array<Array<Object>>] grid The data contents of this sheet
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

        # The column titles for this spreadsheet, as calculated from the provided data.
        # @return [Array<Object>]
        def columns
          @grid[0]
        end

        # The rows values for this spreadsheet, as calculated from the provided data.
        # @return [Array<Object>]
        def rows
          @grid[1...]
        end
      end
    end
  end
end
