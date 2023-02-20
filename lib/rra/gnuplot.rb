require 'open3'

require 'pry'

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
        gnuplot.set 'palette', 'maxcolors %d' % series_colors.length unless opts[:fractional]

        gnuplot.set "palette", "defined ( %s )" % [
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

    CHART_TYPES = [:area, :column]

    attr_reader :palette, :settings, :plot_command

    SET_QUOTED = %w(title output xlabel x2label ylabel y2label clabel cblabel zlabel)

    # This uses an updated version of the gnuplot gem's open, but which uses popen3
    # and prevents that stupid 'decimal_sign in locale is .' output on stderr
    def initialize(title, dataset, &block)
      @title, @dataset = title, dataset
      @settings, @plot_command = [], 'plot'
      @additional_lines = []

      # TODO: This should be a series_themes, and base_themes
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

    # TODO: We may want/need to change these defaults... lets see what happens
    # with columns_and_lines. We may want to also break this into separate
    # plot_for, plot_elements,  etc methods
    def plot(starting: 1, ending: nil, increment: nil, iterator: 'i', elements: [])
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
            # TODO: Default this to column(i)
            '    title %s' % [element[:title] || 'columnheader(i)'],
            element.key?(:with)  ? '    with %s' % element[:with] : nil
          ].compact.join(" \\\n")
        }.join(", \\\n")
      ].join
    end

    # TODO: Probably we need to test this, and/or move it to private. We may
    # even want to just nix this encoding feature entirely..
    def encode_value(value)
      # TODO: this is a crappy encoder. pulled from gnuplot. make it reasonable
      (value =~ /^["'].*['"]$/) ? value : "\"#{value}\""
    end

    def set(key, value = nil)
      @settings << [:set, key,
        (value and SET_QUOTED.include?(key)) ? encode_value(value) : value].compact
    end

    def unset(key)
      @settings << [:unset, key]
    end

    # I'm not crazy about this method name. Can we even delete this maybe..
    # TODO: Stick this in the builder base class?
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

    # TODO: Once we've factored this out, let's make each of these cases a
    # Builder class... and really, we should be able to join chart/lines/etc into
    # a single builder... probably. Let's see what the factoring shows
    def self.chart(dataset, title, opts = {})
      type = opts[:chart_type].downcase.to_sym

      num_cols = dataset[0].length
      palette = RRA::Gnuplot::Palette.new

      # TODO: Probably should just move this into the .new... and then make these private methods
      #       or, maybe, change the syntax in the yml to not have a type. And let each series be a type.
      self.new title, dataset do |gnuplot|
        gnuplot << Array(opts[:additional_lines]) if opts.key? :additional_lines

        case type
          when :area
            # Both:

            # X-axis:
            gnuplot.set 'xdata time'
            # TODO: You'll note that there are cases where these angles are different, below.
            # That should be a param..
            gnuplot.set "xtics", "scale 0 rotate by 45 offset -1.4,-1.4"

            if opts[:is_stacked]
              # TODO: Cashflow: probably needs an is_stacked
              # gnuplot.set 'bmargin at screen 0.5'
              # gnuplot.set "key title 'Expenses'"
              # TODO: Invert the legend order... why is hotels on bottom right, instead of top left
              #
              # TODO: Move this into the above palette section. Probably this needds to be in the yml
              palette.apply_series_colors! gnuplot

              # TODO: I don't think this should be part of is_stacked.. move it into the yaml. Maybe as
              # an additional_lines...
              gnuplot.set 'tics front' # TODO: What's this do?
              gnuplot.set 'xtics 60*60*24*30' # TODO: Is this needed
              gnuplot.set 'xtics out' # TODO: IS this needed?

              # Data related:
              gnuplot.plot starting: num_cols, ending: 2, increment: -1, elements: [
                { using: [1,'(sum [col=2:i] (valid(col) ? column(col) : 0.0))',
                          '((i-2) %% %d)' % [palette.series_colors.length]],
                  with: 'filledcurves x1 fillstyle solid linecolor palette' }
              ]
            else
              # gnuplot.set 'bmargin at screen 0.4'
              # gnuplot.set "key title 'Legend'"
              # TODO: Clean this up, probably put it in the yaml
              Palette.new(
                series_colors: Palette.series_colors_from_themes('Retro Metro')
                ).apply_series_colors! gnuplot
              # gnuplot.ytics "add ('' 0) scale 0"
              # Data:
              gnuplot.plot starting: 2, elements: [
                { using: [1,'((valid(i) ? column(i) : 0.0))','i'],
                  # NOTE: the reason we're not getting borders, is because of the x1
                  # todo: this would be nice 'with filledcurves x1 fillstyle pattern 10 fillcolor palette',
                  with: 'filledcurves x1 fillstyle fillcolor palette' }
              ]
            end
          when :column
            gnuplot.set "style fill solid"

            # Palette
            palette.apply_series_colors! gnuplot, fractional: true

            using_columns = if opts[:is_clustered]
              # Seems like this sets the style of all histograms
              gnuplot.set "style histogram clustered"

              # NOTE: Here, we're setting nil to 0, with the ternary syntax. That
              # should maybe be an option...
              ['(valid(i) ? column(i) : 0.0)','xticlabels(1)']
            else
              gnuplot.set "style", "histogram rowstacked"
              # TODO: Move these into the yaml
              gnuplot.set "boxwidth 0.75 relative"
              gnuplot.set "key title 'Expenses'" # TODO: hmm
              gnuplot.set "xtics", "scale 0 rotate by 45 offset -2.8,-1.4"

              ["i","xtic(1)"]
            end

            gnuplot.plot starting: 2, elements: [
              { using: using_columns,
                with: "histogram linetype palette frac ((i-2) %% %d)/%.1f" % ([
                  palette.series_colors.length]*2)
              }
            ]
          when :column_and_lines
            # NOTE: when merging above , this couples with the !is_clustered
            gnuplot.set "style", "histogram rowstacked"

            # Palette
            # TODO:  I think we can probably nix this function, and remove this line
            palette.apply_series_colors! gnuplot, fractional: true

            # TODO: Let's maybe redo the syntax on this function, probably it should default to starting nil
            # TODO: Maybe it should take a block, for our elements
            gnuplot.plot starting: nil, elements: (1.upto(num_cols-1).map do |i|
              title = dataset[0][i]
              series_type = :column

              # TODO: This code is a little ugly looking..
              if opts.key?(:series_types) and opts[:series_types].key? title&.to_sym
                series_type = opts[:series_types][title.to_sym].downcase.to_sym
              end

              with = case series_type
                when :column
                  # TODO: Can we just specify the color here, and not use the frac?
                  # TODO: don't calculate this maybe, grab it from the palette as a precompute
                  # TODO: Use a modulus here
                  "histograms linetype rgb '%s'" % [palette.series_colors[i-1]]
                when :line # Line
                  "lines smooth unique lc rgb '%s' lt 1 lw 2" % [palette.series_colors[i-1]]
                else
                  raise StandardError, "Unsupported series_type %s" % series_type.inspect
              end

              { using: [i+1, 'xtic(1)'], title: "'%s'" % title, with: with }
            end)
=begin
            gnuplot.plot starting: 2, ending: num_cols-2, elements: [
              { using: ['i', 'xtic(1)'],
                with: 'histograms linetype palette frac ((i-2) %% %d)/%.1f' % ([
                  palette.series_colors.length]*2)
              },
              # These are the rolling average and annual average lines:
              { using: 5, title: 'columnheader(5)', with: "lines smooth unique lc rgb '%s' lt 1 lw 2" % [palette.green] },
              { using: 6, title: 'columnheader(6)', with: "lines smooth unique lc rgb '%s' lt 1 lw 2" % [palette.orange] },
            ]
=end
        end

      end
    end

  end
end
