require 'open3'

module RRA
  class Gnuplot
    class Palette
      BASE_THEMES = {
        solarized_light: {
          base03:  '#002b36',
          base02:  '#073642',
          base01:  '#586e75',
          base00:  '#657b83',
          base0:   '#839496',
          base1:   '#93a1a1',
          base2:   '#eee8d5',
          base3:   '#fdf6e3',
          yellow:  '#b58900',
          orange:  '#cb4b16',
          red:     '#dc322f',
          magenta: '#d33682',
          violet:  '#6c71c4',
          blue:    '#268bd2',
          cyan:    '#2aa198',
          green:   '#859900',

          font:       :base03,
          title:      :font,
          grid:       :base02,
          axis:       :base02,
          key_text:   :font,
          background: :base3
        }
      }

      SERIES_THEMES = {
        # http://www.gnuplotting.org/data/dark2.pal
        'dark2' => ['#1B9E77', '#D95F02', '#7570B3', '#E7298A', '#66A61E',
                    '#E6AB02', '#A6761D', '#666666'],

        # Categorical
        # https://www.heavy.ai/blog/12-color-palettes-for-telling-better-stories-with-your-data
        'Retro Metro' => ["#ea5545", "#f46a9b", "#ef9b20", "#edbf33", "#ede15b",
                        "#bdcf32", "#87bc45", "#27aeef", "#b33dc6"],
        'Dutch Field' => ["#e60049", "#0bb4ff", "#50e991", "#e6d800", "#9b19f5",
                        "#ffa300", "#dc0ab4", "#b3d4ff", "#00bfa0"],
        'River Nights' => ["#b30000", "#7c1158", "#4421af", "#1a53ff", "#0d88e6",
                            "#00b7c7", "#5ad45a", "#8be04e", "#ebdc78"],
        'Spring Pastels' => ["#7eb0d5", "#fd7f6f", "#b2e061", "#bd7ebe", "#ffb55a",
                            "#ffee65", "#beb9db", "#fdcce5", "#8bd3c7"],
        # Sequential
        'Blue to Yellow' => ["#115f9a", "#1984c5", "#22a7f0", "#48b5c4", "#76c68f",
                            "#a6d75b", "#c9e52f", "#d0ee11", "#d0f400"]
        # TODO: Add more sequential from https://www.heavy.ai/blog/12-color-palettes-for-telling-better-stories-with-your-data
      }

      attr_reader :base_colors

      def initialize(opts = {})
        @series_colors = (opts.has_key? :series_colors) ? opts[:series_colors] :
          self.class.series_colors_from_themes( 'Spring Pastels','Retro Metro',
            'Dutch Field', 'River Nights' )
        @base_colors = (opts.has_key? :base_colors) ? opts[:base_colors] :
          BASE_THEMES[:solarized_light]
        @last_series_color = -1
      end

      def series_next!
        @series_colors[(@last_series_color += 1) % @series_colors.length]
      end

      # TODO: I think we don't need this
      def self.series_colors_from_themes(*args)
        args.collect{|arg| SERIES_THEMES[arg]}.flatten
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

      def header
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
      SUPPORTED_ELEMENTS = [ AreaChart, ColumnAndLineChart ]

      attr_accessor :additional_lines
      attr_reader :palette, :settings, :plot_command

      SET_QUOTED = %w(title output xlabel x2label ylabel y2label clabel cblabel zlabel)

      # This uses an updated version of the gnuplot gem's open, but which uses popen3
      # and prevents that stupid 'decimal_sign in locale is .' output on stderr
      def initialize(title, dataset, &block)
        @title, @dataset = title, dataset
        @settings, @plot_command = [], 'plot'
        @additional_lines = []

        @palette = Palette.new

        header!
        block.call(self)
      end

      def script
        [ "$DATA << EOD\n%sEOD\n" % to_csv,
          @settings.map{ |setting| setting.map(&:to_s).join(" ") << "\n" },
          @additional_lines.join("\n"),
          @plot_command, "\n" ].flatten.join
      end

      def <<(lines)
        @additional_lines += lines
      end

      def to_csv
        CSV.generate{ |csv| @dataset.each{|row| csv << row} }
      end

      # TODO: probably iterator should support the range inversion by way of providing
      # an enum to iterator...
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

      # TODO: Probably we need to test this, and/or move it to private. We may
      # even want to just nix this encoding feature entirely..
      def quote_value(value)
        # TODO: this is a crappy encoder. pulled from gnuplot. make it reasonable
        (value =~ /^["'].*['"]$/) ? value : "\"#{value}\""
      end

      def set(key, value = nil)
        @settings << [:set, key,
          (value and SET_QUOTED.include?(key)) ? quote_value(value) : value].compact
      end

      def unset(key)
        @settings << [:unset, key]
      end

      # I'm not crazy about this method name. Can we even delete this maybe..
      # TODO: Stick this in the builder base class? Nah, but, stick this in a config...
      def header!
        # TODO: Maybe supporting a color here would be smart. to do so, append
        #       this to the font declaration: "textcolor linetype 1"
        set 'datafile separator ","'

        set 'title "%s" font "sans,11" textcolor rgb "%s" enhanced' % [
          @title, @palette.title ]

        # TODO: I thhink we can take persist out of here and into the open()
        set ["terminal",
          "wxt size 1200,400 persist",
          # NOTE: This seems to determine the key title font, and nothing else:
          # TODO: How can we set this color? maybe, to Base03...
          "enhanced font 'sans,10'",
          "background rgb '%s'" % [@palette.background] ].join(' ')

        # Background grid:
        # TODO: We need to take these from zero, and maybe move the pallette to (reserved number)
        set "style line 102 lc rgb '%s' lt 0 lw 1" % [@palette.grid]
        set "grid back ls 102"

        # Lighten the y and x axis labels:
        # TODO: We need to take these from zero, and maybe move the pallette to (reserved number)
        set "style line 101 lc rgb '%s' lt 1 lw 1" % [@palette.axis]
        set "border 3 front ls 101"

        # Fonts:
        set 'xtics font ",9"'
        set 'ytics font ",11"'

        # TODO: Color the x and y axis font labels
        # TODO: Color the axis lines

        # I don't know that I want these:
        # gnuplot.xlabel 'Month' # TODO: Do we get this from somewhere
        # gnuplot.ylabel "Amount (USD)" # TODO: Do we get this from somewhere
        set 'timefmt "%m-%y"'

        set 'format x "%b-%y"'
        set 'format y "$ %\'.0f"'

        # TODO: Reenabled
        unset "colorbox"

        # Legend
        # TODO: Why can't we set the key title color?
        set ["key on", "under center", 'textcolor rgb "%s"' % @palette.key_text,
          # 'box lt 3 lc rgb "%s"' % solarized_Base02,
          "enhanced font 'sans,9'" ].join(' ')

        # NOTE: This outputs 'decimal_sign in locale is .' text on the console...
        #       no idea why.
        # This is used to populate numbers with the commas after every three
        # digits:
        set 'decimal locale'
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

      # TODO: I think most of this needs to move into the new, and probably we
      # can delete this method
      def self.chart(dataset, title, opts = {})
        num_cols = dataset[0].length
        palette = RRA::Gnuplot::Palette.new

        # TODO: Probably should just unroll this into the .new... and then make these private methods
        #       or, maybe, change the syntax in the yml to not have a type. And let each series be a type.
        self.new title, dataset do |gnuplot|
          gnuplot.additional_lines << Array(opts[:additional_lines]) if opts.key? :additional_lines

          element_klass = SUPPORTED_ELEMENTS.find{ |element| element.types.any? opts[:chart_type] }

          raise StandardError, "Unsupported chart_type %s" % opts[:chart_type] unless element_klass

          element = element_klass.new opts, gnuplot

          # TODO: Move this to element.series_range in the base class
          series_range = element.reverse_series_range? ? (num_cols-1).downto(1) : 1.upto(num_cols-1)

          gnuplot.plot elements: (series_range.map do |i|
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
      end
    end
  end
end
