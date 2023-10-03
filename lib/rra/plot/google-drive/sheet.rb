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
        # @param [Hash] options The parameters governing this Sheet
        # @option options [String] :default_series_type This parameter is sent to google's addChart method. Expected
        #                                               to be either "COLUMN" or "LINE".
        # @option options [String] :chart_type ('LINE') This parameter determines the kind plot that is built. Expected
        #                                      to be one of: "area", or "column_and_lines"
        # @option options [String] :stacked_type This parameter is sent to google's addChart method. Expected
        #                                        to be either "STACKED" or nil.
        # @option options [Hash<String,String>] :series_colors A Hash, indexed under the name of a series, whose value
        #                                                      is set to the intended html rgb color of that series.
        # @option options [Hash<String,String>] :series_types A Hash, indexed under the name of a series, whose value is
        #                                                     set to either "COLUMN" or "LINE". This setting allows you
        #                                                     to override the :default_series_type, for a specific
        #                                                     series.
        # @option options [Hash<String,String>] :series_line_styles A Hash, indexed under the name of a series, whose
        #                                                           value is set to either "dashed" or nil. This
        #                                                           setting allows you to dash a series on the
        #                                                           resulting plot.
        # @option options [Symbol] :series_target_axis (:left) Either :bottom, :left, or :right. This parameter is sent
        #                                              to google's addChart method, to determine the 'targetAxis' of the
        #                                              plot.
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
