require 'open3'

module RRA
  class Gnuplot
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

      def method_missing(name)
        (@base_colors.has_key?(name)) ? base_color(name) : super(name)
      end

      private

      def base_color(name)
        raise StandardError, "No such base_color \"%s\"" % name unless @base_colors.has_key? name
        @base_colors[name].kind_of?(String) ? @base_colors[name] : base_color(@base_colors[name])
      end
    end

    class ChartBuilder
      def reverse_series_range?
        @reverse_series_range || false
      end

    end

    class AreaChart < ChartBuilder
      def initialize(opts, gnuplot)
        # X-axis:
        gnuplot.set 'xdata', 'time'

        # TODO: You'll note that there are cases where these angles are different, below.
        # That should be an additional_lines line
        gnuplot.set "xtics", "scale 0 rotate by 45 offset -1.4,-1.4"

        # TODO: Does this belong in the cashflow additional lines?
        # gnuplot.set 'bmargin at screen 0.5'
        # gnuplot.set "key title 'Expenses'"
        # TODO: For cashflow, Invert the legend order... why is hotels on bottom right, instead of top left
        # /TODO: Cashflow

        # TODO: Does this belong in wealth growth additional_lines?
        # gnuplot.set 'bmargin at screen 0.4'
        # gnuplot.set "key title 'Legend'"
        # gnuplot.ytics "add ('' 0) scale 0"
        # /TODO: wealth growth

        @reverse_series_range = opts[:is_stacked]
      end

      def using_data
        reverse_series_range? ?
          '(sum [col=2:%{num}] (valid(col) ? column(col) : 0.0))' :
          '(valid(%{num}) ? column(%{num}) : 0.0)'
      end

      def series(title)
        { using: [1, using_data],
          with: "filledcurves x1 fillstyle solid 1.0 fillcolor '%{rgb}'" }
      end

      def self.types
        %w(area)
      end
    end

    class ColumnAndLineChart < ChartBuilder
      def initialize(opts, gnuplot)
        @is_clustered = opts[:is_clustered]

        @series_types = opts[:series_types] || {}

        gnuplot.set "style", "histogram %s" % [ is_clustered? ? "clustered" : "rowstacked"]
        gnuplot.set "style", "fill solid"

        # TODO: Why is 'date there at the origin'
        # TODO: Some reports (income-and-expense-by-intention) need 0 and others need 1
        gnuplot.set "xrange", "[0:]"
      end

      def is_clustered?
        @is_clustered
      end

      def series(title)
        series_type = :column
        using = (series_type == :column && is_clustered?) ?
          '(valid(%{num}) ? column(%{num}) : 0.0)' : '%{num}'

        # TODO: This code is a little ugly looking.. and do we really need to_sym?
        if @series_types.key? title&.to_sym
          series_type = @series_types[title.to_sym].downcase.to_sym
        end

        # TODO: move color into the below with the same way we did num
        with = case series_type
          when :column
            "histograms linetype rgb '%{rgb}'"
          when :line # Line
            "lines smooth unique lc rgb '%{rgb}' lt 1 lw 2"
          else
            raise StandardError, "Unsupported series_type %s" % series_type.inspect
        end

        { using: [using, 'xtic(1)'], with: with }
      end

      def self.types
        %w(COMBO column_and_lines column lines)
      end
    end

    class Plot
      # These are the gnuplot elements, that we currently support:
      ELEMENTS = [ AreaChart, ColumnAndLineChart ]

      attr_accessor :additional_lines
      attr_reader :palette, :settings, :plot_command, :num_cols, :template

      SET_QUOTED = %w(title output xlabel x2label ylabel y2label clabel cblabel zlabel)

      # This uses an updated version of the gnuplot gem's open, but which uses popen3
      # and prevents that stupid 'decimal_sign in locale is .' output on stderr
      def initialize(title, dataset, opts = {})
        @title, @dataset = title, dataset
        @settings, @plot_command = [], 'plot'
        @additional_lines = Array(opts[:additional_lines])
        @num_cols = dataset[0].length
        @template = opts[:template]
        @palette = Palette.new @template[:colors]

        element_klass = ELEMENTS.find{ |element| element.types.any? opts[:chart_type] }

        raise StandardError, "Unsupported chart_type %s" % opts[:chart_type] unless element_klass

        element = element_klass.new opts, self

        # TODO: Move this to element.series_range in the base class
        series_range = element.reverse_series_range? ? (num_cols-1).downto(1) : 1.upto(num_cols-1)

        plot elements: (series_range.map do |i|
          title = dataset[0][i]

          series = element.series title
          vars = {rgb: palette.series_next!, num: i+1}

          # TODO: Can we move this into the rendered line itself maybe, rather than
          # here... that way we do this once, for the whole line
          series[:using] = series[:using].map{ |using| using.to_s % vars }
          series[:with] = series[:with] % vars

          ({title:  "'%s'" % title}.merge ).merge(series)
        end)
      end

      def script
        # TODO: We should probably just pull a @palette.to_h thing, where all the palette colors
        # are added, including those we're not using atm
        vars = {title: @title, title_rgb: @palette.title, background_rgb: @palette.background,
        grid_rgb: @palette.grid, axis_rgb: @palette.axis, key_text_rgb: @palette.key_text}

        [ "$DATA << EOD\n%sEOD\n" % to_csv,
          template[:header] % vars,
          @settings.map{ |setting| setting.map(&:to_s).join(" ") << "\n" },
          @additional_lines.join("\n"),
          @plot_command, "\n" ].flatten.join
      end

      def execute!(persist = true)
        output, errors, status = Open3.capture3 ::Gnuplot.gnuplot(persist),
          stdin_data: script

        # For reasons unknown, this is sent to stderr, in response to the
        # 'set decimal locale' instruction. Which we need to set.
        errors = errors.lines.reject{ |line| /^decimal_sign in locale is/.match(line)}

        raise StandardError, "ledger exited non-zero (%d): %s" % [
          status.exitstatus, errors.join("\n")] unless status.success? or errors.length > 0

        output
      end

      def set(key, value = nil)
        @settings << [:set, key,
          (value and SET_QUOTED.include?(key)) ? quote_value(value) : value].compact
      end

      def unset(key)
        @settings << [:unset, key]
      end

      private

      def to_csv
        CSV.generate{ |csv| @dataset.each{|row| csv << row} }
      end

      # This started out as a kind of ruby-fied interface to the plot command
      # in gnuplot. And, we ended up not needing most of those features, in lieu
      # of just providing the elements. Nonetheless, I'm keeping those features
      # in case we change our mind down the line.
      def plot(starting: nil, ending: nil, increment: nil, iterator: 'i', elements: [])
        plot_for ='for [%s]' % [
          iterator ? '%s=%d' % [iterator, starting || 1] : starting, ending || @dataset[0].length, increment
        ].compact.join(':') if starting

        @plot_command = [
          ['plot', plot_for, '$DATA'].compact.join(' '),
          " \\\n",
          # These elements might as well be 'series' in the way we use them. But,
          # gnuplot's documentation calles them elements. So, I kept that here:
          elements.map.with_index{ |element, i|
            [ element.key?(:using) ? [
                ' ',
                (i.zero?) ? nil : '\'\'',
                'using',
                Array(element[:using]).map(&:to_s).join(':')
              ].compact.join(' ') : nil,
              '    title %s' % [element[:title] || 'columnheader(i)'],
              element.key?(:with)  ? '    with %s' % element[:with] : nil
            ].compact.join(" \\\n")
          }.join(", \\\n")
        ].join
      end

      def quote_value(value)
        # TODO: this is a crappy encoder. pulled from the gnuplot gem. make it reasonable
        (value =~ /^["'].*['"]$/) ? value : "\"#{value}\""
      end
    end
  end
end
