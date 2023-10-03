# frozen_string_literal: true

require 'open3'

module RRA
  class Plot
    # This module contains the code needed to produce Gnuplot .gpi files, from a grid, and
    # styling options.
    module Gnuplot
      # Palette's are loaded from a template, and contain logic related to coloring
      # base elements (fonts/background/line-colors/etc), as well as relating to
      # series/element colors in the plot.
      class Palette
        # @param [Hash] opts The options to configure this palette with
        # @option opts [Hash<Symbol, String>] :base The base colors for this plot. Currently, the following base colors
        #                                           are supported: :title_rgb, :background_rgb, :font_rgb, :grid_rgb,
        #                                           :axis_rgb, :key_text_rgb . This option expects keys to be one of the
        #                                           supported colors, and values to be in the 'standard' html color
        #                                           format, resembling "#rrggbb" (with rr, gg, and bb being a
        #                                           hexadecimal color code)
        #
        # @option opts [Array<String>] :series An array of colors, in the 'standard' html color format. There is no
        #                                      limit to the size of this array.
        def initialize(opts = {})
          @series_colors = opts[:series]
          @base_colors = opts[:base]
          @last_series_color = -1
          @last_series_direction = 1
        end

        # Return the current series color. And, increments the 'current' color pointer, so that a subsequent call to
        # this method returns 'the next color', and continues the cycle. Should there be no
        # further series colors available, at the time of advance, the 'current' color
        # moves back to the first element in the provided :series colors.
        # @return [String] The html color code of the color, before we advanced the series
        def series_next!
          @last_series_color += @last_series_direction
          @series_colors[@last_series_color % @series_colors.length]
        end

        # @!visibility private
        def respond_to_missing?(name, _include_private = false)
          @base_colors.key? name
        end

        # Unhandled methods, are assumed to be base_color requests. And, commensurately, the :base option
        # in the constructor is used to satisfy any such methods
        # @return [String] An html color code, for the requested base color
        def method_missing(name)
          @base_colors.key?(name) ? base_color(name) : super(name)
        end

        # Returns the base colors, currently supported, that were supplied in the {#initialze} base: option
        # @return [Hash<Symbol, String>] An html color code, for the requested base color
        def base_to_h
          # We'll probably want to expand this more at some point...
          { title_rgb: title, background_rgb: background, font_rgb: font,
            grid_rgb: grid, axis_rgb: axis, key_text_rgb: key_text }
        end

        # This is used by some charts, due to gnuplot requiring us to inverse the
        # order of series. The from_origin parameter, is the new origin, by which
        # we'll begin to assign colors, in reverse order
        def reverse_series_colors!(from_origin)
          @last_series_color = from_origin
          @last_series_direction = -1
        end

        private

        def base_color(name)
          raise StandardError, format('No such base_color "%s"', name) unless @base_colors.key? name

          @base_colors[name].is_a?(String) ? @base_colors[name] : base_color(@base_colors[name])
        end
      end

      # This base class offers some helpers, used by our Element classes to handle
      # common options, and keep things DRY.
      class ChartBuilder
        ONE_MONTH_IN_SECONDS = 2_592_000 # 30 days

        # Create a chart
        # @param [Hash] opts options to configure this chart
        # @option opts [Symbol] :domain This option specifies the 'type' of the domain. Currently, the only supported
        #                               type is :monthly
        # @option opts [Integer,Date] :xrange_start The plot domain origin, either the number 1, or a date
        # @option opts [Date] :xrange_end The end of the plot domain
        # @option opts [Hash<Symbol, String>] :axis Axis labels. At the moment, :bottom and :left are supported keys.
        # @param [RRA::Plot::Gnuplot::Plot] gnuplot A Plot to attach this Chart to
        def initialize(opts, gnuplot)
          # TODO: At some point, we probably want to support inverting the key order.
          #       which, as best I can tell, will involve writing a 'fake' chart,
          #       that's not displayed. But which will create a key, which is
          #       displayed, in the order we want
          @gnuplot = gnuplot

          if opts[:domain]
            @domain = opts[:domain].to_sym
            case @domain
            when :monthly
              # This is mostly needed, because gnuplot doesn't always do the best
              # job of automatically detecting the domain bounds...
              gnuplot.set 'xdata', 'time'
              gnuplot.set 'xtics', ONE_MONTH_IN_SECONDS

              dates = gnuplot.column(0).map { |xtic| Date.strptime xtic, '%m-%y' }.sort
              is_multiyear = dates.first.year != dates.last.year

              unless dates.empty?
                opts[:xrange_start] ||= is_multiyear ? dates.first : Date.new(dates.first.year, 1, 1)
                opts[:xrange_end] ||= is_multiyear ? dates.last : Date.new(dates.last.year, 12, 31)
              end
            else
              raise StandardError, format('Unsupported domain %s', @domain.inspect)
            end
          end

          gnuplot.set 'xrange', format_xrange(opts) if xrange? opts
          gnuplot.set 'xlabel', opts[:axis][:bottom] if opts[:axis] && opts[:axis][:bottom]
          gnuplot.set 'ylabel', opts[:axis][:left] if opts[:axis] && opts[:axis][:left]
        end

        # Returns a enumerator, for use by {Plot#plot_command}, when building charts. Mostly,
        # this method is what determines if the series are started from one, going up to numcols. Or, are started
        # from num_cols, and go down to one.
        # @return [Enumerator] An enumerator to progress through the chart's series
        def series_range(num_cols)
          reverse_series_range? ? (num_cols - 1).downto(1) : 1.upto(num_cols - 1)
        end

        # Returns the column number specifier, a string, for use by {Plot#plot_command}, when building charts.
        # In some charts, this is as simple as num + 1. In others, this line can contain more complex gnuplot code.
        # @return [String] Returns the gnuplot formatted series_num, for the series at position num.
        def format_num(num)
          (num + 1).to_s
        end

        private

        def reverse_series_range?
          @reverse_series_range || false
        end

        def format_xrange(opts)
          fmt_parts = %i[xrange_start xrange_end].each_with_object({}) do |attr, ret|
            value = opts[attr]
            value = value.strftime('%m-%y') if value.respond_to?(:strftime)
            ret.merge!(attr => value.is_a?(String) ? format('"%s"', value) : value.to_s)
          end
          format '[%<xrange_start>s:%<xrange_end>s]', fmt_parts
        end

        def xrange?(opts)
          %i[xrange_start xrange_end].any? { |attr| opts[attr] }
        end

        def reverse_series_colors!
          @gnuplot.palette.reverse_series_colors! @gnuplot.num_cols - 1
        end
      end

      # This Chart element contains the logic necessary to render Integrals
      # (shaded areas, under a line), onto the plot canvas.
      class AreaChart < ChartBuilder
        # (see ChartBuilder#initialize)
        # @option opts [TrueClass,FalseClass] :is_stacked Whether the series on this chart are offset from the origin,
        #                                                 or are offset from each other (aka 'stacked on top of each
        #                                                 other')
        def initialize(opts, gnuplot)
          super opts, gnuplot
          @reverse_series_range = opts[:is_stacked]
          reverse_series_colors! if reverse_series_range?
        end

        # The gnuplot data specifier components, for series n
        # @param _ [Integer] Series number
        # @return [Hash<Symbol, Object>] :using and :with strings, for use by gnuplot
        def series(_)
          { using: [1, using_data],
            with: "filledcurves x1 fillcolor '%<rgb>s'" }
        end

        # The chart types we support, intended for use in the chart_type parameter of your plot yaml.
        # This class supports: 'area'
        # @return [Array<String>] Supported chart types.
        def self.types
          %w[area]
        end

        private

        def using_data
          if reverse_series_range?
            '(sum [col=2:%<num>s] (valid(col) ? column(col) : 0.0))'
          else
            '(valid(%<num>s) ? column(%<num>s) : 0.0)'
          end
        end
      end

      # This Chart element contains the logic used to render histograms (bars) along with lines,
      # onto the plot canvas
      class ColumnAndLineChart < ChartBuilder
        # (see ChartBuilder#initialize)
        # @option opts [TrueClass, FalseClass] :is_clustered (false) A flag indicating whether to cluster (true) or
        #                                                    row-stack (false) the bar series.
        # @option opts [Symbol] :columns_rendered_as There are two methods that can be used to render columns
        #                                            (:histograms & :boxes). The :boxes method supports time-format
        #                                            domains. While :histograms supports non-reversed series ranges.
        # @option opts [Hash<String, Symbol>] :series_types A hash, indexed by series name, whose value is either
        #                                                   :column, or :line.
        def initialize(opts, gnuplot)
          super opts, gnuplot
          @is_clustered = opts[:is_clustered]
          @columns_rendered_as = opts[:columns_rendered_as]
          @columns_rendered_as ||= @domain == :monthly ? :boxes : :histograms

          @series_types = {}
          @series_types = opts[:series_types].transform_keys(&:to_s) if opts[:series_types]

          case @columns_rendered_as
          when :histograms
            gnuplot.set 'style', format('histogram %s', clustered? ? 'clustered' : 'rowstacked')
            gnuplot.set 'style', 'fill solid'
          when :boxes
            @reverse_series_range = true
            # This puts a black line around the columns:
            gnuplot.set 'style', 'fill solid border -1'
            reverse_series_colors!

            # TODO: The box width straddles the tic, which, causes the box widths to
            # be half-width on the left and right sides of the plot. Roughly here,
            # we want to expand that xrange start/end by maybe two weeks.
            # This will require a bit more work than we want atm, because:
            # 1. We'd have to change the timefmt, and the grids, to report days
            # 2. We need to move the gnuplot.set in the initializer() into something
            #    farther down the code path.
          else
            raise StandardError, format('Unsupported columns_rendered_as %s', @columns_rendered_as.inspect)
          end
        end

        # Returns the value of the :is_clusted initialization parameter.
        # @return [TrueClass, FalseClass] Whether or not this chart is clustered
        def clustered?
          @is_clustered
        end

        # The gnuplot data specifier components, for series n
        # @param num [Integer] Series number
        # @return [Hash<Symbol, Object>] :using and :with strings, for use by gnuplot
        def series(num)
          type = series_type num
          using = [using(type)]

          using.send(*@columns_rendered_as == :histograms ? [:push, 'xtic(1)'] : [:unshift, '1'])

          { using: using, with: with(type) }
        end

        # Given the provided column number, return either :column, or :line, depending on whether this column
        # has a value, as specified in the initialization parameter :series_types
        # @return [Symbol] Either :column, or :line
        def series_type(num)
          title = @gnuplot.series_name(num)
          @series_types.key?(title) ? @series_types[title].downcase.to_sym : :column
        end

        # (see ChartBuilder#series_range)
        def series_range(num_cols)
          ret = super num_cols
          return ret unless @columns_rendered_as == :boxes

          # We want the lines to draw over the columns. This achieves that.
          # It's possible that you want lines behind the columns. If so, add
          # an option to the class and submit a pr..
          ret.sort_by { |n| series_type(n) == :column ? 0 : 1 }
        end

        # (see ChartBuilder#format_num)
        def format_num(num)
          if reverse_series_range? && series_type(num) == :column
            columns_for_sum = num.downto(1).map do |n|
              # We need to handle empty numbers, in order to fix that weird double-wide column bug
              format '(valid(%<num>s) ? column(%<num>s) : 0.0)', num: n + 1 if series_type(n) == :column
            end
            format '(%s)', columns_for_sum.compact.join('+')
          else
            super(num)
          end
        end

        # The chart types we support, intended for use in the chart_type parameter of your plot yaml.
        # This class supports: COMBO column_and_lines column lines.
        # @return [Array<String>] Supported chart types.
        def self.types
          %w[COMBO column_and_lines column lines]
        end

        private

        def using(type)
          type == :column && clustered? ? '(valid(%<num>s) ? column(%<num>s) : 0.0)' : '%<num>s'
        end

        def with(type)
          case type
          when :column
            "#{@columns_rendered_as} linetype rgb '%<rgb>s'"
          when :line
            "lines smooth unique lc rgb '%<rgb>s' lt 1 lw 2"
          else
            raise StandardError, format('Unsupported series_type %s', series_type.inspect)
          end
        end
      end

      # This class represents, and generates, a gnuplot gpi file. Either to string, or, to the filesystem.
      # This class will typically work with classes derived from {RRA::Plot::Gnuplot::ChartBuilder}, and
      # an instance of this class is provided as a parameter to the #initialize method of a ChartBuilder.
      # @attr_reader [Array<String>] additional_lines Arbitrary lines, presumably of gnuplot code, that are appended to
      #                                               the generated gpi, after the settings, and before the plot
      #                                               commands(s).
      # @attr_reader [Hash[String, String]] settings A hash of setting to value pairs, whech are transcribed (via the
      #                                              'set' directive) to the plot
      # @attr_reader [Hash[Symbol, Object]] template A hash containing a :header string, and a :colors {Hash}. These
      #                                              objects are used to construct the aesthetics of the generated gpi.
      #                                              For more details on what options are supported in the :colors key,
      #                                              see the colors section of:
      #                                              {https://github.com/brighton36/rra/blob/main/resources/gnuplot/default.yml default.yml}
      # @attr_reader [RRA::Plot::Gnuplot::ChartBuilder] element An instance of {Plot::ELEMENTS}, to which plot directive
      #                                                         generation is delegated.
      # @attr_reader [Array<Array<String>>] dataset A grid, whose first row contains the headers, and in which each
      #                                             additional row's first element, is a keystone.
      class Plot
        # These are the gnuplot elements, that we currently support:
        ELEMENTS = [AreaChart, ColumnAndLineChart].freeze
        # These attributes were pulled from the gnuplot gem, and indicate which #set key's require string quoting.
        # This implementation isn't very good, but, was copied out of the Gnuplot gem
        SET_QUOTED = %w[title output xlabel x2label ylabel y2label clabel cblabel zlabel].freeze
        # This is a string formatting specifier, used to composed a plot directive, to gnuplot
        PLOT_COMMAND_LINE = ['%<using>s', 'title %<title>s', 'with %<with>s'].compact.join(" \\\n    ").freeze

        attr_accessor :additional_lines
        attr_reader :settings, :template, :element, :dataset

        # Create a plot
        # @param [String] title The title of this plot
        # @param [Array<Array<String>>] dataset A grid, whose first row contains the headers, and in which each
        #                                       additional row's first element, is a keystone.
        # @param [Hash] opts options to configure this plot, and its {element}. Unrecognized options, in this
        #                    parameter, are delegated to the specified {chart_type} for further handling.
        # @option opts [Symbol] :additional_lines ([]) see {additional_lines}
        # @option opts [Symbol] :template see {template}
        # @option opts [String] :chart_type A string, that is matched against .types of available ELEMENTS, and
        #                                   used to initialize an instance of a matched class, to create our {element}
        def initialize(title, dataset, opts = {})
          @title = title
          @dataset = dataset
          @settings = []
          @additional_lines = Array(opts[:additional_lines])
          @template = opts[:template]

          element_klass = ELEMENTS.find { |element| element.types.any? opts[:chart_type] }
          raise StandardError, format('Unsupported chart_type %s', opts[:chart_type]) unless element_klass

          @element = element_klass.new opts, self
        end

        # Assembles a gpi file's contents, and returns them as a string
        # @return [String] the generated gpi file
        def script
          vars = { title: @title }.merge palette.base_to_h

          [format("$DATA << EOD\n%sEOD\n", to_csv),
           format(template[:header], vars),
           @settings.map { |setting| setting.map(&:to_s).join(' ') << "\n" },
           format(@additional_lines.join("\n"), vars),
           plot_command, "\n"].flatten.join
        end

        # Runs the gnuplot command, feeding the contents of {script} to it's stdin and returns the output.
        # raises StandardError, citing errors, if gnuplot returns errors.
        # @return [String] the output of gnuplot, with some selective squelching of output
        def execute!(persist: true)
          output, errors, status = Open3.capture3 Gnuplot.gnuplot(persist), stdin_data: script

          # For reasons unknown, this is sent to stderr, in response to the
          # 'set decimal locale' instruction. Which we need to set.
          errors = errors.lines.reject { |line| /^decimal_sign in locale is/.match(line) }

          unless status.success? || !errors.empty?
            raise StandardError,
                  format('gnuplot exited non-zero (%<status>s): %<errors>s',
                         status: status.exitstatus,
                         errors: errors.join("\n"))
          end

          output
        end

        # Transcribes a 'set' directive, into the generated plot, with the given key as the set variable name,
        # and the provided value, as that set's value. Some values (See {SET_QUOTED}) are interpolated. Others
        # are merely transcribed directly as provided, without escaping.
        # @param [String] key The gnuplot variable you wish to set
        # @param [String] value The value to set to, if any
        # @return [void]
        def set(key, value = nil)
          quoted_value = value && SET_QUOTED.include?(key) ? quote_value(value) : value
          @settings << [:set, key, quoted_value].compact
          nil
        end

        # Transcribes an 'unset' directive, into the generated plot, with the given key as the unset variable name.
        # @param [String] key The gnuplot variable you wish to unset
        # @return [void]
        def unset(key)
          @settings << [:unset, key]
          nil
        end

        # Returns column n of dataset, not including the header row
        # @param [Integer] num The column number to return
        # @return [Array<String>] The column that was found, from top to bottom
        def column(num)
          dataset[1...].map { |row| row[num] }
        end

        # Returns the header row, at position num
        # @param [Integer] num The series number to query
        # @return [String] The name of the series, at row num
        def series_name(num)
          dataset[0][num]
        end

        # Returns the number of columns in the dataset, including the keystone
        # @return [Integer] the length of dataset[0]
        def num_cols
          dataset[0].length
        end

        # The current {Palette} instance that we're using for our color queries
        def palette
          @palette ||= Palette.new @template[:colors]
        end

        private

        def to_csv
          CSV.generate { |csv| dataset.each { |row| csv << row } }
        end

        def plot_command
          # NOTE: n == 0 is the keystone.
          plot_command_lines = element.series_range(num_cols).map.with_index do |n, i|
            title = series_name n

            # Note that the gnuplot calls these series 'elements', but, we're keeping
            # with series
            series = { title: "'#{title}'" }.merge(element.series(n))
            series[:using] = format(' %<prefix>s using %<usings>s',
                                    prefix: i.zero? ? nil : ' \'\'',
                                    usings: Array(series[:using]).map(&:to_s).join(':'))

            format(format(PLOT_COMMAND_LINE, series), { rgb: palette.series_next!, num: element.format_num(n) })
          end

          format("plot $DATA \\\n%<lines>s", lines: plot_command_lines.join(", \\\n"))
        end

        def quote_value(value)
          value =~ /^["'].*['"]$/ ? value : "\"#{value}\""
        end
      end
    end
  end
end
