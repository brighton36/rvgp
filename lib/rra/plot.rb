# frozen_string_literal: true

require_relative 'plot/gnuplot'

module RRA
  # This class assembles grids into a series of plots, given a plot specification
  # yaml. Once a grid is assembled, it's dispatched to a driver ({GoogleDrive} or {Gnuplot})
  # for rendering.
  # Here's an example plot specification, included in the default project build as
  # {https://github.com/brighton36/rra/blob/main/resources/skel/app/plots/wealth-growth.yml wealth-growth.yml}, as
  # created by the new_project command:
  #   title: "Wealth Growth (%{year})"
  #   glob: "%{year}-wealth-growth.csv"
  #   grid_hacks:
  #     store_cell: !!proc >
  #       (cell) ? cell.to_f.abs : nil
  #   google:
  #     chart_type: area
  #     axis:
  #       left: "Amount"
  #       bottom: "Date"
  #   gnuplot:
  #     chart_type: area
  #     domain: monthly
  #     axis:
  #       left: "Amount"
  #       bottom: "Date"
  #     additional_lines: |+
  #       set xtics scale 0 rotate by 45 offset -1.4,-1.4
  #       set key title ' '
  #       set style fill transparent solid 0.7 border
  #
  # The yaml file is required to have :title and :glob parameters. Additionally,
  # the following parameter groups are supported: :grid_hacks, :gnuplot, and :google.
  #
  # The :gnuplot section of this file, is merged with the contents of
  # {https://github.com/brighton36/rra/blob/main/resources/gnuplot/default.yml default.yml}, and passed to the {RRA::Plot::Gnuplot}
  # constructor. See the {RRA::Plot::Gnuplot::Plot#initialize} method for more details on what parameters are supported
  # in this section. NOTE: Depending on the kind of chart being specified, some initialize options are specific to the
  # chart being built, and those options will be documented in the constructor for that specific chart. ie:
  # {RRA::Plot::Gnuplot::AreaChart#initialize} or {RRA::Plot::Gnuplot::ColumnAndLineChart#initialize}.
  #
  # The :google section of this file, is provided to {RRA::Plot::GoogleDrive::Sheet#initialize}. See this method for
  # details on supported options.
  #
  # The :grid_hacks section of this file, contains miscellaneous hacks to the dataset. These include: :keystone,
  # :store_cell, :select_rows, :sort_rows_by, :sort_columns_by, :truncate_rows, :switch_rows_columns, and
  # :truncate_columns. These options are documented in: {RRA::GridReader#initialize} and {RRA::GridReader#to_grid}.
  #
  # @attr_reader [String] path A path to the location of the input yaml, as provided to #initialize
  # @attr_reader [RRA::Yaml] yaml The yaml object, containing the parameters of this plot
  # @attr_reader [String] glob A string containing wildcards, used to match input grids in the filesystem. This
  #                            parameter is expected to be found inside the yaml[:glob], and will generally look
  #                            something like: "%\{year}-wealth-growth.csv" or
  #                            "%\{year}-property-incomes-%\{property}.csv".
  #                            The variables which are supported, include 'the year' of a plot, as well as whatever
  #                            variables are defined in a plot's glob_variants ('property', as was the case
  #                            above.) glob_variants are output by grids, and detected in the filenames those grids
  #                            produce by the {RRA::Plot.glob_variants} method.
  class Plot
    attr_reader :path, :yaml, :glob

    # The required keys, expected to exist in the plot yaml
    REQUIRED_FIELDS = %i[glob title].freeze

    # The path to rra's 'default' include file search path. Any '!!include' directives encountered in the plot yaml,
    # will search this location for targets.
    GNUPLOT_RESOURCES_PATH = [RRA::Gem.root, '/resources/gnuplot'].join

    # This exception is raised when a provided yaml file, is missing required
    # attributes.
    class MissingYamlAttribute < StandardError
      MSG_FORMAT = 'Missing one or more required fields in %<path>s: %<fields>s'

      def initialize(path, fields)
        super format(MSG_FORMAT, path: path, fields: fields)
      end
    end

    # This exception is raised when a provided yaml file, stipulates an invalid
    # {glob} attribute
    class InvalidYamlGlob < StandardError
      MSG_FORMAT = 'Plot file %<path>s is missing a required \'year\' parameter in glob'

      def initialize(path)
        super format(MSG_FORMAT, path: path)
      end
    end

    # Create a plot, from a specification yaml
    # @param [String] path The path to a specification yaml
    def initialize(path)
      @path = path

      @yaml = RRA::Yaml.new path, [RRA.app.config.project_path, GNUPLOT_RESOURCES_PATH]

      missing_attrs = REQUIRED_FIELDS.reject { |f| yaml.key? f }
      raise MissingYamlAttribute, yaml.path, missing_attrs unless missing_attrs.empty?

      @glob = yaml[:glob] if yaml.key? :glob
      raise InvalidYamlGlob, yaml.path unless /%\{year\}/.match glob

      grids_corpus = Dir[RRA.app.config.build_path('grids/*')]

      @variants ||= self.class.glob_variants(glob, grids_corpus) +
                    self.class.glob_variants(glob, grids_corpus, year: 'all')

      @title = yaml[:title] if yaml.key? :title
    end

    def variants(name = nil)
      name ? @variants.find { |v| v[:name] == name } : @variants
    end

    def variant_files(variant_name)
      variants(variant_name)[:files]
    end

    def title(variant_name)
      @title % variants(variant_name)[:pairs]
    end

    def output_file(name, ext)
      RRA.app.config.build_path format('plots/%<name>s.%<ext>s', name: name, ext: ext)
    end

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

        RRA::GridReader.new(variant_files(variant_name), rvopts).to_grid(gopts)
      end
    end

    def column_titles(variant_name)
      grid(variant_name)[0]
    end

    def series(variant_name)
      grid(variant_name)[1..]
    end

    def gnuplot(name)
      @gnuplots ||= {}
      @gnuplots[name] ||= RRA::Plot::Gnuplot::Plot.new title(name), grid(name), gnuplot_options
    end

    def script(name)
      gnuplot(name).script
    end

    def show(name)
      gnuplot(name).execute!
    end

    def write!(name)
      File.write output_file(name, 'gpi'), gnuplot(name).script
    end

    # This returns what plot variants are possible, given the glob, against the
    # provided files.
    # If pair_values contains key: value combinations, then, any of the returned
    # variants will be sorted under the key:value provided . (Its really just meant
    # for year: 'all'}  atm..)
    def self.glob_variants(glob, corpus, pair_values = {})
      variant_names = glob.scan(/%\{([^ }]+)/).flatten.map(&:to_sym)

      glob_vars = variant_names.to_h { |key| [key, '(.+)'] }
      variant_matcher = Regexp.new format(glob, glob_vars)

      corpus.each_with_object([]) do |file, ret|
        matches = variant_matcher.match File.basename(file)

        if matches
          pairs = variant_names.map.with_index do |key, i|
            [key, pair_values.key?(key.to_sym) ? pair_values[key] : matches[i + 1]]
          end.to_h

          pair_i = ret.find_index { |variant| variant[:pairs] == pairs }
          if pair_i
            ret[pair_i][:files] << file
          else
            ret << { name: File.basename(glob % pairs, '.*'),
                     pairs: pairs,
                     files: [file] }
          end
        end

        ret
      end.compact
    end

    def self.all(plot_directory_path)
      Dir.glob(format('%s/*.yml', plot_directory_path)).map { |path| new path }
    end

    def google_options
      @google_options = yaml[:google] if yaml.key? :google
    end

    private

    def grid_hacks
      @grid_hacks = yaml.key?(:grid_hacks) ? yaml[:grid_hacks] : {}
    end

    def gnuplot_options
      @gnuplot_options ||= begin
        gnuplot_options = yaml[:gnuplot] || {}
        template = RRA::Yaml.new(format('%s/default.yml', GNUPLOT_RESOURCES_PATH))
        gnuplot_options.merge(template: template)
      end
    end
  end
end
