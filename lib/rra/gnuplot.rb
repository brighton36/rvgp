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
        'Spring Pastels' => ["#fd7f6f", "#7eb0d5", "#b2e061", "#bd7ebe", "#ffb55a",
                            "#ffee65", "#beb9db", "#fdcce5", "#8bd3c7"],
        # Sequential
        'Blue to Yellow' => ["#115f9a", "#1984c5", "#22a7f0", "#48b5c4", "#76c68f",
                            "#a6d75b", "#c9e52f", "#d0ee11", "#d0f400"]
        # TODO: Add more sequential from https://www.heavy.ai/blog/12-color-palettes-for-telling-better-stories-with-your-data
      }

      attr_reader :base_colors, :series_colors

      def initialize(opts = {})
        @series_colors = (opts.has_key? :series_colors) ? opts[:series_colors] :
          self.class.series_colors_from_themes( 'Spring Pastels','Retro Metro',
            'Dutch Field', 'River Nights' )
        @base_colors = (opts.has_key? :base_colors) ? opts[:base_colors] :
          BASE_THEMES[:solarized_light]
      end

      def apply_series_colors!(gnuplot, opts = {})
        gnuplot.set 'palette maxcolors %d' % series_colors.length unless opts[:fractional]

        # TODO Let's make this a multiline at maybe 80 chars or so...
        gnuplot.set "palette defined ( %s )" % [
          series_colors.collect.with_index{ |color, i|
            # NOTE: Some charts (histogram) don't support indexed palettes, and
            # instead support color spectrums
            index = opts[:fractional] ? ("%.6f" % [i.to_f/(series_colors.length)]) : ("%d" % i)
            "%s '%s'" % [index, color]
          }.join(', ')  ]
        nil
      end

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

    # This is a replacement for the gnuplot Dataset, which, has a number of bugs
    # that make it useless for us.
    # TODO: Remove this class. It's no longer needed.
    class DataSet
      # TODO: Move this dataset parameter into the gnuplot class, and move the related functions there
      # Probably we can just remove this class entirely
      def initialize(cmd, plot_attrs, opts = {})
        @cmd, @plot_attrs, @opts = cmd, plot_attrs, opts
      end

      def inline?
        (@opts.has_key?(:inline)) ? @opts[:inline] : true
      end

      def name
        @opts.has_key?(:name) ? @opts[:name] : 'DATA'
      end

      def to_tmppath
        unless @datafile
          @datafile = Tempfile.new 'gnuplot'
          @datafile.write to_csv
          @datafile.close
        end

        @datafile.path
      end

      def plot_args(io = "")
        sep = " \\\n  "
        io << [ (inline?) ? ('$%s' % name) : ("'%s'" % [to_tmppath]),
          sep, @plot_attrs.join(sep)].join
      end

      def apply!(plot)
        # This only reason this should trigger, is if we're calling apply! more
        # than once:
        raise StandardError, "Unimplemented" unless (
          (plot.cmd == 'plot') and (plot.arbitrary_lines.kind_of? Array) )

        plot.set 'datafile separator ","'

        plot.cmd = @cmd
        plot.data ||= []
        plot.data << self
      end

    end

    CHART_TYPES = [:area, :column]

    attr_reader :script, :palette
    attr_accessor :data, :arbitrary_lines, :settings, :cmd # TODO: These were copied from gnuplot, let's choose better variables

    # TODO: Let's pick a better anme
    QUOTED = %w(title output xlabel x2label ylabel y2label clabel cblabel zlabel)

    # This is an updated version of the gnuplot gem's open, but which uses popen3
    # and prevents that stupid 'decimal_sign in locale is .' output on stderr
    def initialize(title, dataset, &block)
      @settings = []
      @arbitrary_lines = []
      @data = []
      @dataset = dataset
      @cmd = 'plot'

      @title = title
      # TODO: This should be a series_themes, and base_themes

      @palette = Palette.new

      @script = String.new
      header!
      block.call(self)

      # TODO: THis was copied over...
      @script << to_gplot
      @script << store_datasets
    end

    def to_csv
      CSV.generate{ |csv| @dataset.each{|row| csv << row} }
    end


    # TODO: Refactor
    def set(var, value = "")
      value = "\"#{value}\"" if QUOTED.include? var unless value =~ /^'.*'$/
      @settings << [ :set, var, value ]
    end

    # TODO: Refactor
    def unset(var)
      @settings << [:unset, var]
    end

    # TODO: This was copied over. Refactor
    def to_gplot(io = "")
      # The "plot '-'" format was just buggy. This encoding works more reliably
      io << "$DATA << EOD\n%sEOD\n" % to_csv

      @settings.each do |setting|
        io << setting.map(&:to_s).join(" ") << "\n"
      end
      @arbitrary_lines.each { |line| io << line << "\n" }

      io
    end

    # TODO: This was copied over. Refactor
    def store_datasets (io = "")
      if @data.size > 0
        io << @cmd << " " << @data.collect { |e| e.plot_args }.join(", ")
        io << "\n"

        #v = @data.collect { |ds| ds.to_gplot }
        #io << v.compact.join("e\n")
      end

      io
    end


    def header!
      # TODO: We should probably encode the data at the top

      # TODO: Maybe supporting a color here would be smart. to do so, append
      #       this to the font declaration: "textcolor linetype 1"
      set 'title "%s" font "Bitstream Vera,11" textcolor rgb "%s" enhanced' % [
        @title, @palette.title ]

      # TODO: I thhink we can take persist out of here and into the open()
      set ["terminal",
        "wxt size 1200,400 persist",
        # NOTE: This seems to determine the key title font, and nothing else:
        # TODO: How can we set this color? maybe, to Base03...
        "enhanced font 'Bitstream Vera,10'",
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

      # TODO: Reenabled
      unset "colorbox"

      # Legend
      # TODO: Why can't we set the key title color?
      set ["key on",
      "under center",
      'textcolor rgb "%s"' % @palette.key_text,
      # 'box lt 3 lc rgb "%s"' % solarized_Base02,
      "enhanced font 'Bitstream Vera,9'"
      ].join(' ')

      # TODO: Why is this outputting text on console...
      # This  to populate numbers with the commas after every three
      # digits:
      set 'decimal locale'
    end

    def execute!(persist = true)
      output, errors, status = Open3.capture3 ::Gnuplot.gnuplot(persist),
        stdin_data: @script

      # For reasons unknown, this is sent to stderr, in response to the
      # 'set decimal locale' instruction. Which we need to set.
      errors = errors.lines.reject{ |line| /^decimal_sign in locale is/.match(line)}

      raise StandardError, "ledger exited non-zero (%d): %s" % [
        status.exitstatus, errors.join("\n")] unless status.success? or errors.length > 0

      output
    end

    # TODO: Maybe take this type out of here, and into the options...
    def self.chart(dataset, title, opts = {})
      type = opts[:chart_type].downcase.to_sym

      num_cols = dataset[0].length
      palette = RRA::Gnuplot::Palette.new

      # TODO: Probably should just move this into the .new... and then make these private methods
      self.new title, dataset do |gnuplot|
        case type
          when :area
            gnuplot.set 'xdata time'
            gnuplot.set 'timefmt "%m-%y"'
            gnuplot.set 'xrange ["%s":"%s"]' % [dataset[1][0], dataset[dataset.length-1][0]]
            gnuplot.unset 'mxtics'
            gnuplot.set 'mytics 2'
            gnuplot.set 'grid xtics ytics mytics'
            gnuplot.set 'title "Wealthgrow"'
            gnuplot.set 'ylabel "Amount"' # TODO
            gnuplot.set 'style fill solid 1 noborder'

            # for [<var> = <start> : <end> {: <incr>}]
            RRA::Gnuplot::DataSet.new('plot for [i=2:%d:1]' % num_cols,
              0.upto(num_cols-2).map{ |i|
               'using 1:%d with filledcurves x1 title "%s" linecolor rgb "%s"%s ' % [
               i+2, dataset[0][i+1], palette.series_colors[i], (i == 0) ? ', \'\'' : '' ]
              } ).apply! gnuplot

          when :stacked_area
            # TODO: I think this is always a stacked area. I think
            # Both:
            gnuplot.set 'timefmt "%b-%y"'

            # X-axis:
            gnuplot.set 'xdata time'
            gnuplot.set 'format x "%b-%y"'
            gnuplot.set "xtics", "scale 0 rotate by 45 offset -1.4,-1.4"

            # Y-axis:
            gnuplot.set 'format y "$ %\'.0f"'

            if opts[:is_stacked]
              # TODO: Cashflow: probably needs an is_stacked
              # gnuplot.set 'bmargin at screen 0.5'
              # gnuplot.set "key title 'Expenses'"
              # TODO: Invert the legend order... why is hotels on bottom right, instead of top left
              #
              # TODO: Move this into the above palette section. Probably this needds to be in the yml
              palette.apply_series_colors! gnuplot

              gnuplot.set 'tics front' # TODO: What's this do?
              gnuplot.set 'xtics 60*60*24*30'
              gnuplot.set "xtics", "scale 0 rotate by 45 offset -1.4,-1.4"
              gnuplot.set 'xtics out'

              # Data related:
              RRA::Gnuplot::DataSet.new('plot for [i=%d:2:-1]' % num_cols, [
                'using 1:(sum [col=2:i] (valid(col) ? column(col) : 0.0)):((i-2) %% %d)' % [
                  palette.series_colors.length],
                'with filledcurves x1 fillstyle solid linecolor palette',
                'title columnheader(i)'
                ] ).apply! gnuplot
            else
              # TODO: Wealth Grow
              # gnuplot.set 'bmargin at screen 0.4'
              # gnuplot.set "key title 'Legend'"
              # TODO: Clean this up, probably put it in the constructor and header
              Palette.new(
                series_colors: Palette.series_colors_from_themes('Retro Metro')
                ).apply_series_colors! gnuplot
              # gnuplot.ytics "add ('' 0) scale 0"
              # Data:
              RRA::Gnuplot::DataSet.new('plot for [i=2:%d]' % num_cols, [
              "using 1:((valid(i) ? column(i) : 0.0)):i",
              # NOTE: The reason we're not getting borders, is because of the x1
              # TODO: This would be nice 'with filledcurves x1 fillstyle pattern 10 fillcolor palette',
              'with filledcurves x1 fillstyle fillcolor palette',
              'title columnheader(i)'
              ] ).apply! gnuplot
            end
          when :column
            # TODO: DRY these two subformats out
            if opts[:is_clustered]
              gnuplot.set "style data histogram"
              gnuplot.set "style histogram clustered"
              gnuplot.set "style fill solid"
              gnuplot.set 'timefmt "%b-%y"'

              # X-axis
              gnuplot.set 'format x "%b-%y"'

              # Y-axis
              gnuplot.set 'format y "$ %\'.0f"'

              # Palette
              palette.apply_series_colors! gnuplot, fractional: true

              # Data related
              RRA::Gnuplot::DataSet.new('plot for [i=2:%d]' % [num_cols], [
                'using (valid(i) ? column(i) : 0.0):xticlabels(1)',
                'linetype palette frac ((i-2) %% %d)/%.1f title columnheader(i)' % [
                  palette.series_colors.length, palette.series_colors.length]
                ] ).apply! gnuplot
            else
              gnuplot.set "style", "data histograms"
              gnuplot.set "style", "histogram rowstacked"
              gnuplot.set "boxwidth 0.75 relative"
              gnuplot.set "style fill solid"
              gnuplot.set 'timefmt "%b-%y"'
              gnuplot.set "key title 'Expenses'"

              # Palette
              palette.apply_series_colors! gnuplot, fractional: true

              # X-axis
              gnuplot.set 'format x "%b-%y"'
              gnuplot.set "xtics", "scale 0 rotate by 45 offset -2.8,-1.4"

              # Y-axis
              gnuplot.set 'format y "$ %\'.0f"'

              # Data related:
              RRA::Gnuplot::DataSet.new('plot for [i=2:%d]' % num_cols, [
                "using i:xtic(1) linetype palette frac ((i-2) %% %d)/%.1f" % [
                  palette.series_colors.length, palette.series_colors.length],
                'title columnheader(i)'
                ] ).apply! gnuplot
            end
          when :column_and_lines
            gnuplot.set "style", "data histograms"
            gnuplot.set "style", "histogram rowstacked"
            gnuplot.set "boxwidth 0.75 relative"
            gnuplot.set "style fill solid"
            gnuplot.set 'timefmt "%b-%y"'
            gnuplot.set "key title 'Incomes'"

            # Palette
            palette.apply_series_colors! gnuplot, fractional: true

            # smooth Line palette
            gnuplot.set "style line 103 lc rgb '%s' lt 1 lw 2" % [palette.green]
            gnuplot.set "style line 104 lc rgb '%s' lt 1 lw 2" % [palette.orange]

            # X-axis
            gnuplot.set 'format x "%b-%y"'
            gnuplot.set "xtics", "scale 0 rotate by 45 offset -2.8,-1.4"

            # Y-axis
            gnuplot.set 'format y "$ %\'.0f"'

            # Data related:
            RRA::Gnuplot::DataSet.new('plot for [i=2:%d]' % [num_cols-2], [
              'using i:xtic(1) linetype palette frac ((i-2) %% %d)/%.1f title columnheader(i),' % [
                palette.series_colors.length, palette.series_colors.length],
              # TODO: We need to decide how we're going to work these, see the note above
              # These are the rolling average and annual average lines:
              "\"\" using 5 smooth unique title columnheader(5) with lines linestyle 103,",
              "\"\" using 6 smooth unique title columnheader(6) with lines linestyle 104"
              ] ).apply! gnuplot
        end

      end
    end

  end
end
