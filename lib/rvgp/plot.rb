# frozen_string_literal: true

require_relative 'plot/gnuplot'

module RVGP
  # This class assembles grids into a series of plots, given a plot specification
  # yaml. Once a grid is assembled, it's dispatched to a driver ({GoogleDrive} or {Gnuplot})
  # for rendering.
  # Here's an example plot specification, included in the default project build as
  # {https://github.com/brighton36/rvgp/blob/main/resources/skel/app/plots/wealth-growth.yml wealth-growth.yml}, as
  # created by the new_project command:
  # ```
  # title: "Wealth Growth (%{year})"
  # glob: "%{year}-wealth-growth.csv"
  # aggregates: ["year"]
  # grid_hacks:
  #   store_cell: !!proc >
  #     (cell) ? cell.to_f.abs : nil
  # google:
  #   chart_type: area
  #   axis:
  #     left: "Amount"
  #     bottom: "Date"
  # gnuplot:
  #   chart_type: area
  #   domain: monthly
  #   axis:
  #     left: "Amount"
  #     bottom: "Date"
  #   additional_lines: |+
  #     set xtics scale 0 rotate by 45 offset -1.4,-1.4
  #     set key title ' '
  #     set style fill transparent solid 0.7 border
  # ```
  #
  # The yaml file is required to have :title and :glob parameters. Additionally,
  # the following parameter groups are supported: :aggregates, :grid_hacks, :gnuplot, and :google.
  #
  # The :aggregates section of this file specifies whether the plot should produce additional plot, using a wildcare, in
  # lieu of a single value, in the specified key. So, given the above wealth growth example, in addition to a plot per
  # year, there would be an 'all-wealth-growth' plot that is generated, which outputs over the domain of all years in
  # the produced wealth-growth grids.
  #
  # The :gnuplot section of this file, is merged with the contents of
  # {https://github.com/brighton36/rvgp/blob/main/resources/gnuplot/default.yml default.yml}, and passed to the {RVGP::Plot::Gnuplot}
  # constructor. See the {RVGP::Plot::Gnuplot::Plot#initialize} method for more details on what parameters are supported
  # in this section. NOTE: Depending on the kind of chart being specified, some initialize options are specific to the
  # chart being built, and those options will be documented in the constructor for that specific chart. ie:
  # {RVGP::Plot::Gnuplot::AreaChart#initialize} or {RVGP::Plot::Gnuplot::ColumnAndLineChart#initialize}.
  #
  # The :google section of this file, is provided to {RVGP::Plot::GoogleDrive::Sheet#initialize}. See this method for
  # details on supported options.
  #
  # The :grid_hacks section of this file, contains miscellaneous hacks to the dataset. These include: :keystone,
  # :store_cell, :select_rows, :sort_rows_by, :sort_columns_by, :truncate_rows, :switch_rows_columns, and
  # :truncate_columns. These options are documented in: {RVGP::Utilities::GridQuery#initialize} and
  # {RVGP::Utilities::GridQuery#to_grid}.
  #
  # @attr_reader [String] path A path to the location of the input yaml, as provided to #initialize
  # @attr_reader [RVGP::Utilities::Yaml] yaml The yaml object, containing the parameters of this plot
  # @attr_reader [String] glob A string containing wildcards, used to match input grids in the filesystem. This
  #                            parameter is expected to be found inside the yaml[:glob], and will generally look
  #                            something like: "%\\{year}-wealth-growth.csv" or
  #                            "%\\{year}-property-incomes-%\\{property}.csv".
  #                            The variables which are supported, include 'the year' of a plot, as well as whatever
  #                            variables are defined in a plot's glob_variants ('property', as was the case
  #                            above.) glob_variants are output by grids, and detected in the filenames those grids
  #                            produce by the {RVGP::Plot.glob_variants} method.
  class Plot
    attr_reader :path, :yaml, :glob

    # The required keys, expected to exist in the plot yaml
    REQUIRED_FIELDS = %i[glob title].freeze

    # The path to rvgp's 'default' include file search path. Any '!!include' directives encountered in the plot yaml,
    # will search this location for targets.
    GNUPLOT_RESOURCES_PATH = [RVGP::Gem.root, '/resources/gnuplot'].join

    # This exception is raised when a provided yaml file, is missing required
    # attributes.
    class MissingYamlAttribute < StandardError
      # @!visibility private
      MSG_FORMAT = 'Missing one or more required fields in %<path>s: %<fields>s'

      def initialize(path, fields)
        super format(MSG_FORMAT, path: path, fields: fields)
      end
    end

    # This exception is raised when a provided yaml file, stipulates an invalid
    # {glob} attribute
    class InvalidYamlGlob < StandardError
      # @!visibility private
      MSG_FORMAT = 'Plot file %<path>s contains one or more invalid keys: %<keys>s, in glob parameter'

      def initialize(path)
        super format(MSG_FORMAT, path: path, invalid_keys: RVGP::Plot::Glob::INVALID_KEYS.map(&:to_s).join(', '))
      end
    end

    # This exception is raised when a provided yaml file, stipulates an improperly formatted
    # parameter
    class InvalidYamlParameter < StandardError
      # @!visibility private
      MSG_FORMAT = 'Plot file %<path>s contains an invalid or improperly formatted \"%<attribute>s\" parameter'

      def initialize(path, attribute)
        super format(MSG_FORMAT, path: path, attribute: attribute)
      end
    end

    # This class is used by {RVGP::Plot} as an abstraction for working with the glob parameter of a plot yaml, against
    # paths in a filesystem. While this class mostly resembles the traditional glob functions, there are some additional
    # functions for reversing the glob, and parameterizing the results. In addition, the syntax resembles ruby's
    # format() syntax, more so than glob syntax (at the consequence of many of glob's features). Probably I should use a
    # different name for this class and parameter, but, it works at the moment. And largely expresses the idea.
    #
    # Note that an instance of this class, is principally intended for use as a return value by the
    # {RVGP::Plot::Glob.variants} method.
    # @attr_reader [Hash<String,<String,Bool>>] values The key to value pairs, of what patterns this glob represents.
    #                                           This attribute is used by the plot, to represent a 'variant'
    # @attr_reader [Array<String>] files An array of paths, that this glob matched against.
    class Glob
      MATCH_KEYS = /%(?><([^ >]+)>|\{([^ }]+))/.freeze
      INVALID_KEYS = %i[basename values keys files].freeze

      attr_reader :values
      attr_accessor :files

      # Create a glob match, using the provided fields
      # @param [String] from_s The glob that produced this result
      # @param [Hash<String,<String,Bool>>] values The values for the match, given the keys provided by the glob's
      #                                             from_s
      # @param [Array<String>] files The files that belong to the match
      def initialize(from_s, values, files)
        @from_s = from_s
        @values = values
        @files = files
      end

      # The basename of this glob, composed by applying the values_as_strings, to the glob
      # @return [String] The fully composed name of this glob
      def name
        File.basename(format(@from_s, values_as_strings), '.*')
      end

      # This method is mostly identical to {Glob.values}, however, wildcards are converted
      # @return [Hash<String,String>] The fully composed name of this glob, with bool entries converted into a
      #                               human-readable representation.
      def values_as_strings
        str_all = I18n.t('commands.plot.wildcard')
        values.transform_values { |val| val == true ? str_all : val }.to_h
      end

      # Return the glob keys. As specified in the constructor, presumably calculated using the glob string itself
      # @return [Array<String>] The keys from {values}
      def keys
        @values.keys
      end

      # Calls to this instance, which match a key in the {values} will return the value itself as a String or Bool
      def method_missing(method, *_, &block)
        values.key?(method) ? values[method] : super
      end

      # @!visibility private
      def respond_to_missing?(method, _ = false)
        values.key?(method) || super
      end

      # This returns what file variants are possible, given a glob, when matched against the
      # provided haystack(corpus) of file names.
      # If wildcards contains a key: Then, any permutation in the provided corpus that could match in place
      # of the key, is included in a match. This is commonly used for {year} matches, where we want to aggregate
      # the data of all years into a single result.
      # @param [String] glob A string that matches 'variables'(keys) in the form of \\{variablename} specifiers
      # @param [Array<String>] corpus An array of file paths. The paths are matched against the glob, and
      #                               separated based on the variables found, in their names.
      # @param [Array<Symbol>] wildcards An array of key names, which won't be separated into independent glob returns
      # @return [Array<Glob>] The resulting matches for this query
      def self.variants(from_str, corpus, wildcards = [])
        keys = from_str.scan(MATCH_KEYS).flatten.compact.map(&:to_sym)

        variant_matcher = Regexp.new format(from_str, keys.to_h { |key| [key, '(.+)'] })

        corpus.each_with_object([]) do |file, ret|
          matches = variant_matcher.match File.basename(file)

          if matches
            pairs = keys.map.with_index do |key, i|
              [key, wildcards.include?(key.to_sym) ? true : matches[i + 1]]
            end.to_h

            pair_i = ret.find_index { |glob| glob.values == pairs }
            if pair_i
              ret[pair_i].files << file
            else
              ret << new(from_str, pairs, [file])
            end
          end

          ret
        end
      end

      # A quick test against a glob string, to determine if there are any obvious errors with it.
      # @param [String] glob A glob string.
      # @return [Bool] True if valid, False if not
      def self.valid?(glob)
        glob.scan(MATCH_KEYS).flatten.compact.map(&:to_sym).intersection(INVALID_KEYS).length.zero?
      end
    end

    # Create a plot, from a specification yaml
    # @param [String] path The path to a specification yaml
    def initialize(path)
      @path = path

      @yaml = RVGP::Utilities::Yaml.new path, [RVGP.app.config.project_path, GNUPLOT_RESOURCES_PATH]

      missing_attrs = REQUIRED_FIELDS.reject { |f| yaml.key? f }
      raise MissingYamlAttribute, yaml.path, missing_attrs unless missing_attrs.empty?

      @glob = yaml[:glob] if yaml.key? :glob
      raise InvalidYamlGlob, yaml.path unless RVGP::Plot::Glob.valid? glob

      grids_corpus = Dir[RVGP.app.config.build_path('grids/*')]

      @variants ||= RVGP::Plot::Glob.variants(glob, grids_corpus)

      if yaml.key?(:aggregates) &&
         (!yaml[:aggregates].is_a?(Array) || yaml[:aggregates].any? { |str| !str.is_a? String })
        raise InvalidYamlParameter, yaml.path, 'aggregates'
      end

      yaml[:aggregates]&.each { |agg| @variants += RVGP::Plot::Glob.variants(glob, grids_corpus, [agg.to_sym]) }

      @title = yaml[:title] if yaml.key? :title
    end

    # In the case that a name is provided, limit the return to the variant of the provided :name.
    # If no name is provided, all variants in this plot are returned. Variants are determined
    # by the yaml parameter :glob, as applied to the grids found in the build/grids/* path.
    # @param [String] name (nil) Limit the return to this variant, if set
    # @return [Hash<Symbol, Object>] The hash will return name, :pairs, and :files keys,
    #                                that contain the variant details.
    def variants(name = nil)
      name ? @variants.find { |v| v.name == name } : @variants
    end

    # This method returns only the :files parameter, of the {#variants} return.
    # @param [String] variant_name (nil) Limit the return to this variant, if set
    # @return [Array<String>] An array of grid paths
    def variant_files(variant_name)
      variants(variant_name).files
    end

    # The plot title, of the given variant
    # @param [String] variant_name The :name of the variant you're looking to title
    # @return [String] The title of the plot
    def title(variant_name)
      @title % variants(variant_name).values_as_strings
    end

    # Generate an output file path, for the given variant. Typically this is a .csv grid, in the build/grids
    # subdirectory of your project folder.
    # @param [String] name The :name of the variant you're looking for
    # @param [String] ext The file extension you wish to append, to the return
    # @return [String] The path to the output file, of the plot
    def output_file(name, ext)
      RVGP.app.config.build_path format('plots/%<name>s.%<ext>s', name: name, ext: ext)
    end

    # Generate and return, a plot grid, for the given variant.
    # @param [String] variant_name The :name of the variant you're looking for
    # @return [Array<Array<Object>>] The grid, as an array of arrays.
    def grid(variant_name)
      @grid ||= {}
      @grid[variant_name] ||= begin
        gopts = {}
        rvopts = {
          store_cell: if grid_hacks.key?(:store_cell)
                        ->(cell) { grid_hacks[:store_cell].call cell: cell }
                      else
                        ->(cell) { cell ? cell.to_f : nil }
                      end
        }

        # Grid Reader Options:
        rvopts[:keystone] = grid_hacks[:keystone] if grid_hacks.key? :keystone

        if grid_hacks.key? :select_rows
          rvopts[:select_rows] = ->(name, data) { grid_hacks[:select_rows].call name: name, data: data }
        end

        # to_grid Options
        gopts[:truncate_rows] = grid_hacks[:truncate_rows].to_i if grid_hacks.key? :truncate_rows
        gopts[:truncate_columns] = grid_hacks[:truncate_columns].to_i if grid_hacks.key? :truncate_columns
        gopts[:switch_rows_columns] = grid_hacks[:switch_rows_columns] if grid_hacks.key? :switch_rows_columns
        gopts[:sort_rows_by] = ->(row) { grid_hacks[:sort_rows_by].call row: row } if grid_hacks.key? :sort_rows_by

        if grid_hacks.key? :sort_columns_by
          gopts[:sort_cols_by] = ->(column) { grid_hacks[:sort_columns_by].call column: column }
        end

        RVGP::Utilities::GridQuery.new(variant_files(variant_name), rvopts).to_grid(gopts)
      end
    end

    # Return the column titles, on the plot for a given variant
    # @param [String] variant_name The :name of the variant you're looking for
    # @return [Array<String>] An array of strings, representing the column titles
    def column_titles(variant_name)
      grid(variant_name)[0]
    end

    # Return the portion of the grid, containing series labels, and their data.
    # @param [String] variant_name The :name of the variant you're looking for
    # @return [Array<Array<Object>>] The portion of the grid, that contains series data
    def series(variant_name)
      grid(variant_name)[1..]
    end

    # Return the google plot options, from the yaml of this plot.
    # @return [Hash] The contents of the google: section of this plot's yml
    def google_options
      @google_options = yaml[:google] if yaml.key? :google
    end

    # Return the gnuplot object, for a given variant
    # @param [String] name The :name of the variant you're looking for
    # @return [RVGP::Plot::Gnuplot::Plot] The gnuplot
    def gnuplot(name)
      @gnuplots ||= {}
      @gnuplots[name] ||= RVGP::Plot::Gnuplot::Plot.new title(name), grid(name), gnuplot_options
    end

    # Return the rendered gnuplot code, for a given variant
    # @param [String] name The :name of the variant you're looking for
    # @return [String] The gnuplot code that represents this variant
    def script(name)
      gnuplot(name).script
    end

    # Execute the rendered gnuplot code, for a given variant. Typically, this opens a gnuplot
    # window.
    # @param [String] name The :name of the variant you're looking for
    # @return [void]
    def show(name)
      gnuplot(name).execute!
    end

    # Write the gnuplot code, for a given variant, to the :output_file
    # @param [String] name The :name of the variant you're looking for
    # @return [void]
    def write!(name)
      output_path = output_file(name, 'gpi')
      File.write output_path, gnuplot(name).script
      RVGP::CachedPta.invalidate! output_path
    end

    # Return all the plot objects, initialized from the yaml files in the plot_directory_path
    # @param [String] plot_directory_path A path to search, for (plot) yml files
    # @return [Array<RVGP::Plot>] An array of the plots, available in the provided directory
    def self.all(plot_directory_path)
      Dir.glob(format('%s/*.yml', plot_directory_path)).map { |path| new path }
    end

    private

    def grid_hacks
      @grid_hacks = yaml.key?(:grid_hacks) ? yaml[:grid_hacks] : {}
    end

    def gnuplot_options
      @gnuplot_options ||= begin
        gnuplot_options = yaml[:gnuplot] || {}
        template = RVGP::Utilities::Yaml.new(format('%s/default.yml', GNUPLOT_RESOURCES_PATH))
        gnuplot_options.merge(template: template)
      end
    end
  end
end
