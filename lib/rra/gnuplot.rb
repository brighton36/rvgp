# frozen_string_literal: true

require 'open3'

module RRA
  class Gnuplot
    # Palette's are loaded from a template, and contain logic related to coloring
    # base elements (fonts/background/line-colors/etc), as well as relating to
    # series/element colors in the plot.
    class Palette
      attr_reader :base_colors

      def initialize(opts = {})
        @series_colors = opts[:series]
        @base_colors = opts[:base]
        @last_series_color = -1
        @last_series_direction = 1
      end

      def series_next!
        @last_series_color += @last_series_direction
        @series_colors[@last_series_color % @series_colors.length]
      end

      def respond_to_missing?(name, *)
        @base_colors.key? name
      end

      def method_missing(name)
        @base_colors.key?(name) ? base_color(name) : super(name)
      end

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

      # TODO: At some point, we probably want to support inverting the key order.
      #       which, as best I can tell, will involve writing a 'fake' chart,
      #       that's not displayed. But which will create a key, which is
      #       displayed, in the order we want
      def initialize(opts, gnuplot)
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

            if !dates.empty?
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

      def format_num(num)
        num+1
      end

      def reverse_series_range?
        @reverse_series_range || false
      end

      def series_range(num_cols)
        reverse_series_range? ? (num_cols - 1).downto(1) : 1.upto(num_cols - 1)
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
    end

    # This Chart element contains the logic necessary to render Integrals
    # (shaded areas, under a line), onto the plot canvas.
    class AreaChart < ChartBuilder
      def initialize(opts, gnuplot)
        @reverse_series_range = opts[:is_stacked]
        gnuplot.palette.reverse_series_colors! gnuplot.num_cols - 1 if reverse_series_range?
        super opts, gnuplot
      end

      def using_data
        if reverse_series_range?
          '(sum [col=2:%<num>s] (valid(col) ? column(col) : 0.0))'
        else
          '(valid(%<num>s) ? column(%<num>s) : 0.0)'
        end
      end

      def series(_)
        { using: [1, using_data],
          with: "filledcurves x1 fillstyle solid 1.0 fillcolor '%<rgb>s'" }
      end

      def self.types
        %w[area]
      end
    end

    # This Chart element contains the logic used to render bars, and/or lines,
    # onto the plot canvas
    class ColumnAndLineChart < ChartBuilder
      def initialize(opts, gnuplot)
        super opts, gnuplot
        @is_clustered = opts[:is_clustered]
        @columns_rendered_as = opts[:columns_rendered_as]
        @columns_rendered_as ||= @domain == :monthly ? :boxes : :histograms

        @series_types = {}
        @series_types = opts[:series_types].transform_keys(&:to_s) if opts[:series_types]

        # There are two methods that can be used to render columns (:histograms & :boxes)
        # The :boxes method supports time-format domains. While :histograms supports
        # non-reversed series ranges.
        case @columns_rendered_as
        when :histograms
          gnuplot.set 'style', format('histogram %s', clustered? ? 'clustered' : 'rowstacked')
          gnuplot.set 'style', 'fill solid'
        when :boxes
          @reverse_series_range = true
          # This puts a black line around the columns:
          gnuplot.set 'style', 'fill solid border -1'

          # TODO The box width straddles the tic, which, causes the box widths to
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

      def clustered?
        @is_clustered
      end

      def series(num)
        type = series_type num
        using = [using(type)]

        using.send(*@columns_rendered_as == :histograms ? [:push, 'xtic(1)'] : [:unshift, '1'])

        { using: using, with: with(type) }
      end

      def self.types
        %w[COMBO column_and_lines column lines]
      end

      def series_type(num)
        title = @gnuplot.series_name(num)
        @series_types.key?(title) ? @series_types[title].downcase.to_sym : :column
      end

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

      def series_range(num_cols)
        ret = super num_cols
        return ret unless @columns_rendered_as == :boxes

        # We want the lines to draw over the columns. This achieves that.
        # It's possible that you want lines behind the columns. If so, add
        # an option to the class and submit a pr..
        ret.sort_by { |n| series_type(n) == :column ? 0 : 1 }
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

    # This class generates a gnuplot file. Either to string, or, the filesystem
    #
    # NOTE: We assume that the first row in the dataset, is a header row. And,
    #       that the first column, is the series label
    class Plot
      # These are the gnuplot elements, that we currently support:
      ELEMENTS = [AreaChart, ColumnAndLineChart].freeze
      SET_QUOTED = %w[title output xlabel x2label ylabel y2label clabel cblabel zlabel].freeze
      PLOT_COMMAND_LINE = ['%<using>s', 'title %<title>s', 'with %<with>s'].compact.join(" \\\n    ").freeze

      attr_accessor :additional_lines
      attr_reader :settings, :template, :element, :dataset

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

      def script
        vars = { title: @title }.merge palette.base_to_h

        [format("$DATA << EOD\n%sEOD\n", to_csv),
         format(template[:header], vars),
         @settings.map { |setting| setting.map(&:to_s).join(' ') << "\n" },
         format(@additional_lines.join("\n"), vars),
         plot_command, "\n"].flatten.join
      end

      def execute!(persist: true)
        output, errors, status = Open3.capture3 Gnuplot.gnuplot(persist), stdin_data: script

        # For reasons unknown, this is sent to stderr, in response to the
        # 'set decimal locale' instruction. Which we need to set.
        errors = errors.lines.reject { |line| /^decimal_sign in locale is/.match(line) }

        unless status.success? || !errors.empty?
          raise StandardError,
                format('ledger exited non-zero (%<status>s): %<errors>s',
                       status: status.exitstatus, errors: errors.join("\n"))
        end

        output
      end

      def set(key, value = nil)
        quoted_value = value && SET_QUOTED.include?(key) ? quote_value(value) : value
        @settings << [:set, key, quoted_value].compact
      end

      def unset(key)
        @settings << [:unset, key]
      end

      # Returns column n of dataset, not including the header row
      def column(num)
        dataset[1...].map { |row| row[num] }
      end

      # Returns the header row, at position num
      def series_name(num)
        dataset[0][num]
      end

      # Returns the number of columns in the dataset, including the series_label
      def num_cols
        dataset[0].length
      end

      # The current palette that we're operating off of
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
        # TODO: this is a crappy encoder. pulled from the gnuplot gem. make it reasonable
        value =~ /^["'].*['"]$/ ? value : "\"#{value}\""
      end
    end
  end
end
