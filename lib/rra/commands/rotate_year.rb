# frozen_string_literal: true

require 'tempfile'

module RRA
  module Commands
    # @!visibility private
    # This class contains the handling of the 'rotate_year' command. Note that
    # there is no rake integration in this command, as that function is irrelevent
    # to the notion of an 'export'.
    class RotateYear < RRA::Base::Command
      accepts_options OPTION_ALL, OPTION_LIST

      # @!visibility private
      def execute!
        puts I18n.t('commands.rotate_year.operations_header')

        operations = []

        unless File.directory? RotateYear.historical_path
          operations << I18n.t('commands.rotate_year.operation_mkdir', path: RotateYear.historical_path)
        end

        operations += targets.map(&:operation_descriptions).flatten

        operations.each do |operation|
          puts I18n.t('commands.rotate_year.operation_element', operation: operation)
        end

        print I18n.t('commands.rotate_year.confirm_operation_prompt')

        if $stdin.gets.chomp != I18n.t('commands.rotate_year.confirm_operation')
          puts [RRA.pastel.red(I18n.t('error.error')), I18n.t('commands.rotate_year.operation_aborted')].join(' : ')
          exit 1
        end

        RRA.app.ensure_build_dir! 'feeds/historical'

        super
      end

      def self.historical_path
        RRA.app.config.project_path('feeds/historical')
      end

      # @!visibility private
      # This class represents a transformer that's not 'historical'. Which, makes it different from the
      # TransformerTarget. 'historical' is determined by whether its input_file is located in a '/historical/' basedir.
      class Target < RRA::Base::Command::Target
        attr_reader :transformer

        # @!visibility private
        # This is used as a catch in the mv! method
        class GitError < StandardError
        end

        # Create a new RotateYear::Target
        # @param [RRA::Base::Transformer] transformer An instance of either {RRA::Transformers::CsvTransformer}, or
        #                                             {RRA::Transformers::JournalTransformer}, to use as the basis
        #                                             for this target.
        def initialize(transformer)
          super transformer.as_taskname, transformer.label
          @transformer = transformer
        end

        # @!visibility private
        def operation_descriptions
          [I18n.t('commands.rotate_year.operation_rotate', name: File.basename(transformer.file))]
        end

        # @!visibility private
        def description
          I18n.t 'commands.rotate_year.target_description', basename: File.basename(transformer.file)
        end

        # @!visibility private
        def name_parts
          raise StandardError, format('Unable to determine year from %s', name) unless /^(\d+)(.+)/.match name

          [Regexp.last_match(1).to_i, Regexp.last_match(2)]
        end

        # @!visibility private
        def year
          name_parts.first
        end

        def git_repo?
          @is_git_repo = begin
            git! 'branch'
            true
          rescue GitError
            false
          end
        end

        # @!visibility private
        def git!(*args)
          @git_prefix ||= begin
            output, exit_code = Open3.capture2 'which git'
            raise GitError, output unless exit_code.to_i.zero?

            [output.chomp, '-C', Shellwords.escape(RRA.app.project_path)]
          end

          output, exit_code = Open3.capture2((@git_prefix + args.map { |a| Shellwords.escape a }).join(' '))

          raise GitError, output unless exit_code.to_i.zero?

          output
        end

        # @!visibility private
        # This move will use git, if the source file is in a repo. If not, it'll use the system mv
        def mv!(source, dest)
          raise GitError if !git_repo? || !%r{^#{RRA.app.project_path}/(.+)}.match(source)

          project_relative_source = Regexp.last_match 1

          raise GitError unless /^#{project_relative_source}$/.match(git!('ls-files'))

          git! 'mv', project_relative_source, dest
        rescue GitError
          FileUtils.mv source, dest
        end

        # @!visibility private
        def execute(_)
          historical_feed_path = [File.dirname(transformer.input_file), 'historical'].join('/')
          rotated_basename = name_parts.tap { |parts| parts[0] += 1 }.join

          FileUtils.mkdir_p historical_feed_path

          # TODO: Is any of this working? It's very close. Test.
          mv! transformer.input_file, historical_feed_path

          rotated_input_path = format('%<dir>s/%<file>s.%<ext>s',
                                      dir: File.dirname(transformer.input_file), file: rotated_basename, ext: 'csv')

          FileUtils.touch rotated_input_path

          rotated_transformer_path = format('%<dir>s/%<basename>s.%<ext>s',
                                            dir: File.dirname(transformer.file), basename: rotated_basename, ext: 'yml')

          File.write rotated_transformer_path, rotated_transformer_contents

          git! 'add', rotated_transformer_path if git_repo?

          git! 'add', rotated_input_path if git_repo?

          nil
        end

        # @!visibility private
        # This method returns a rotated transformer, based on the contents of the legacy transformer.
        # Root elements are preserved, but, child elements are not. Income and expense sections are
        # pre-populated with catch-all rules.
        def rotated_transformer_contents
          elements = File.read(transformer.file).scan(/^[^\n ].+/)
          from = elements.map { |r| ::Regexp.last_match(1) if /^from:[ \t]*(.+)/.match r }
                         .compact.first&.tr('"\'', '')&.split(':')&.first

          elements.map do |line|
            if /^(expense|income):/.match line
              direction = ::Regexp.last_match(1)
              format("%<direction>s:\n  - match: /.*/\n    to: %<to>s",
                     direction: direction,
                     to: [from, direction == 'expense' ? 'Expenses' : 'Income', 'Unknown'].compact.join(':'))
            else
              line
            end
          end.join("\n").tr(year.to_s, (year + 1).to_s)
        end

        # All possible Transformer Targets that the project has defined.
        # @return [Array<RRA::Base::Command::TransformerTarget>] A collection of targets.
        def self.all
          RRA.app.transformers.map do |transformer|
            new transformer unless File.dirname(transformer.input_file).split('/').last == 'historical'
          end.compact
        end

        private

        def rotated_input_file_path
          rotate_path transformer.input_file
        end

        def rotate_path(path)
          parts = path.split('/')
          filepart = parts.pop

          return path unless /\A(\d+)(.*)\Z/.match(filepart)

          (parts + [[::Regexp.last_match(1).to_i + 1, ::Regexp.last_match(2)].join]).join('/')
        end
      end
    end
  end
end
