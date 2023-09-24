# frozen_string_literal: true

require_relative 'plot/gnuplot'

module RRA
  # This class assembles grids into a series of plots, using a plot specification
  # yaml. Once a grid is assembled, it's dispatched to a driver (google or gnuplot)
  # for rendering.
  class Plot
    attr_reader :path, :yaml, :glob, :sort_by_rows, :truncate_rows,
                :switch_rows_columns

    REQUIRED_FIELDS = %i[glob title].freeze
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
    # glob attribute
    class InvalidYamlGlob < StandardError
      MSG_FORMAT = 'Plot file %<path>s is missing a required \'year\' parameter in glob'

      def initialize(path)
        super format(MSG_FORMAT, path: path)
      end
    end

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
        # TODO: All of this probably needs to be wrapped into the GridReader.

        gopts = {}
        rvopts = {}

        # Grid Reader Options:
        rvopts[:series_label] = grid_hacks[:keystone] if grid_hacks.key? :keystone

        rvopts[:store_cell] = if grid_hacks.key?(:store_cell)
                                lambda do |cell|
                                  grid_hacks[:store_cell].call cell: cell
                                end
                              else
                                lambda do |cell|
                                  cell ? cell.to_f : nil
                                end
                              end

        if grid_hacks.key? :select_rows
          rvopts[:select_rows] = lambda do |name, data|
            grid_hacks[:select_rows].call name: name, data: data
          end
        end

        # Grid Options
        if grid_hacks.key? :sort_rows_by
          gopts[:sort_by_rows] = lambda do |row|
            grid_hacks[:sort_rows_by].call row: row
          end
        end

        if grid_hacks.key? :sort_columns_by
          gopts[:sort_by_cols] = lambda do |column|
            grid_hacks[:sort_columns_by].call column: column
          end
        end

        gopts[:truncate_rows] = grid_hacks[:truncate_rows].to_i if grid_hacks.key? :truncate_rows
        gopts[:switch_rows_columns] = grid_hacks[:switch_rows_columns] if grid_hacks.key? :switch_rows_columns
        # TODO: gopts should probably switch to :truncate_columns, and then we can tighten these 3 lines up
        gopts[:truncate_cols] = grid_hacks[:truncate_columns].to_i if grid_hacks.key? :truncate_columns

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
