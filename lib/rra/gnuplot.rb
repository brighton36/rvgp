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
      end

      def series_next!
        @series_colors[(@last_series_color += 1) % @series_colors.length]
      end

      def respond_to_missing?(name, *)
        @base_colors.key? name
      end

      def method_missing(name)
        @base_colors.key?(name) ? base_color(name) : super(name)
      end

      private

      def base_color(name)
        raise StandardError, format('No such base_color "%s"', name) unless @base_colors.key? name

        @base_colors[name].is_a?(String) ? @base_colors[name] : base_color(@base_colors[name])
      end
    end

    # This module offers some helpers, used by our Element classes to keep things DRY.
    module ChartBuilder
      def reverse_series_range?
        @reverse_series_range || false
      end

      def series_range(num_cols)
        reverse_series_range? ? (num_cols - 1).downto(1) : 1.upto(num_cols - 1)
      end
    end

    # This Chart element contains the logic necessary to render Integrals
    # (shaded areas, under a line), onto the plot canvas.
    class AreaChart
      include ChartBuilder

      def initialize(opts, gnuplot)
        # NOTE: This is a bit assumptive... but, I think it holds true for just
        # about every report we're going to produce
        gnuplot.set 'xdata', 'time'
        @reverse_series_range = opts[:is_stacked]
      end

      def using_data
        if reverse_series_range?
          '(sum [col=2:%<num>d] (valid(col) ? column(col) : 0.0))'
        else
          '(valid(%<num>d) ? column(%<num>d) : 0.0)'
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
    class ColumnAndLineChart
      include ChartBuilder

      def initialize(opts, gnuplot)
        @is_clustered = opts[:is_clustered]

        @series_types = if opts[:series_types]
                          opts[:series_types].transform_keys(&:to_s)
                        else
                          {}
                        end

        gnuplot.set 'style', format('histogram %s', clustered? ? 'clustered' : 'rowstacked')
        gnuplot.set 'style', 'fill solid'

        # TODO: Why is 'date there at the origin'
        # TODO: Some reports (income-and-expense-by-intention) need 0 and others need 1
        gnuplot.set 'xrange', '[0:]'
      end

      def clustered?
        @is_clustered
      end

      def series(title)
        series_type = if @series_types.key? title
                        @series_types[title].downcase.to_sym
                      else
                        :column
                      end

        { using: [using(series_type), 'xtic(1)'], with: with(series_type) }
      end

      def self.types
        %w[COMBO column_and_lines column lines]
      end

      private

      def using(type)
        if type == :column && clustered?
          '(valid(%<num>d) ? column(%<num>d) : 0.0)'
        else
          '%<num>d'
        end
      end

      def with(type)
        case type
        when :column
          "histograms linetype rgb '%<rgb>s'"
        when :line
          "lines smooth unique lc rgb '%<rgb>s' lt 1 lw 2"
        else
          raise StandardError, format('Unsupported series_type %s', series_type.inspect)
        end
      end
    end

    # This class generates a gnuplot file. Either to string, or, the filesystem
    class Plot
      # These are the gnuplot elements, that we currently support:
      ELEMENTS = [AreaChart, ColumnAndLineChart].freeze
      SET_QUOTED = %w[title output xlabel x2label ylabel y2label clabel cblabel zlabel].freeze

      attr_accessor :additional_lines
      attr_reader :palette, :settings, :plot_command, :num_cols, :template, :element, :dataset

      def initialize(title, dataset, opts = {})
        @title = title
        @dataset = dataset
        @settings = []
        @plot_command = 'plot' # TODO: wtf is this
        @additional_lines = Array(opts[:additional_lines])
        @num_cols = dataset[0].length # TODO: put this in an accessor
        @template = opts[:template]
        @palette = Palette.new @template[:colors] # TODO: I think we can put this in an accessor

        element_klass = ELEMENTS.find { |element| element.types.any? opts[:chart_type] }
        raise StandardError, format('Unsupported chart_type %s', opts[:chart_type]) unless element_klass

        @element = element_klass.new opts, self
      end

      def script
        # TODO: We should probably just pull a @palette.to_h thing, where all the palette colors
        # are added, including those we're not using atm
        vars = { title: @title, title_rgb: @palette.title, background_rgb: @palette.background,
                 grid_rgb: @palette.grid, axis_rgb: @palette.axis, key_text_rgb: @palette.key_text }

        [format("$DATA << EOD\n%sEOD\n", to_csv),
         format(template[:header], vars),
         @settings.map { |setting| setting.map(&:to_s).join(' ') << "\n" },
         @additional_lines.join("\n") % vars,
         plot_command, "\n"].flatten.join
      end

      def execute!(persist = true)
        output, errors, status = Open3.capture3 Gnuplot.gnuplot(persist),
          stdin_data: script

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

      private

      def to_csv
        CSV.generate { |csv| dataset.each{ |row| csv << row } }
      end

      def plot_command
        # TODO: Move this into the loop below
        elements = element.series_range(num_cols).map do |i|
          title = dataset[0][i]
          series = element.series title

          {title:  "'%s'" % title, num: i+1 }.merge(series)
        end

        [
          ['plot', '$DATA'].compact.join(' '),
          " \\\n",
          # These elements might as well be 'series' in the way we use them. But,
          # gnuplot's documentation calles them elements. So, I kept that here:
          elements.map.with_index { |element, i|
            vars = { rgb: palette.series_next!, num: element[:num] }

            [element.key?(:using) ? [
                ' ',
                (i.zero?) ? nil : '\'\'',
                'using',
                Array(element[:using]).map(&:to_s).join(':')
              ].compact.join(' ') : nil,
              '    title %s' % [element[:title] || 'columnheader(i)'],
              element.key?(:with)  ? '    with %s' % element[:with] : nil
            ].compact.join(" \\\n") % vars
          }.join(", \\\n")
        ].join
      end

      def quote_value(value)
        # TODO: this is a crappy encoder. pulled from the gnuplot gem. make it reasonable
        value =~ /^["'].*['"]$/ ? value : "\"#{value}\""
      end
    end
  end
end
