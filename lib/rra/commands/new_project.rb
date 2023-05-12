# frozen_string_literal: true

require_relative '../fakers/fake_feed'
require_relative '../fakers/fake_transformer'

module RRA
  module Commands
    # This class handles the request to create a new RRA project.
    class NewProject < RRA::CommandBase
      EXPENSE_DESCRIPTION_POOL_SIZE = 50
      INCOME_DESCRIPTION_POOL_SIZE = 2

      attr_reader :errors, :app_dir, :project_name

      def initialize(*args) # rubocop:disable Lint/MissingSuper
        @errors = []
        @app_dir = args.first
        @errors << I18n.t('commands.new_project.errors.missing_app_dir') unless @app_dir && !@app_dir.empty?
      end

      def execute!
        confirm_operation = I18n.t('commands.new_project.confirm_operation')
        # Let's make sure we don't accidently overwrite anything
        if File.directory? app_dir
          print [RRA.pastel.yellow(I18n.t('error.warning')),
                 I18n.t('commands.new_project.directory_exists_prompt', dir: app_dir)].join(' : ')
          if $stdin.gets.chomp != confirm_operation
            puts [RRA.pastel.red(I18n.t('error.error')),
                  I18n.t('commands.new_project.operation_aborted')].join(' : ')
            exit 1
          end
        end

        # Let's get the project name
        @project_name = nil
        loop do
          print I18n.t('commands.new_project.project_name_prompt')
          @project_name = $stdin.gets.chomp
          unless @project_name.empty?
            print I18n.t('commands.new_project.project_name_confirmation', project_name: @project_name)
            break if $stdin.gets.chomp == confirm_operation
          end
        end

        logger = StatusOutputRake.new pastel: RRA.pastel
        %i[project_directory bank_feeds transformers app config].each do |step|
          logger.info self.class.name, I18n.t(format('commands.new_project.initialize.%s', step)) do
            send format('initialize_%s', step).to_sym
          end
        end

        puts I18n.t('commands.new_project.completed_banner', journal_path: project_journal_path)
      end

      private

      def initialize_project_directory
        @warnings = []
        # Create the directory:
        if Dir.exist? app_dir
          @warnings << [I18n.t('commands.new_project.errors.directory_exists', dir: app_dir)]
        else
          Dir.mkdir app_dir
        end

        # Create the sub directories:
        %w[build feeds journals transformers].each do |dir|
          full_dir = [app_dir, dir].join('/')
          if Dir.exist? full_dir
            @warnings << [I18n.t('commands.new_project.errors.directory_exists', dir: full_dir)]
          else
            Dir.mkdir full_dir
          end
        end

        # TODO: Maybe we should cp_r the skel, in full, and move project-name.journal to a constant...
        FileUtils.cp RRA::Gem.root.resources('skel/Rakefile').to_s, app_dir
        FileUtils.cp RRA::Gem.root.resources('skel/project-name.journal').to_s, project_journal_path

        { warnings: @warnings, errors: [] }
      end

      def initialize_bank_feeds
        this_year.downto(this_year - 5).each do |year|
          File.write destination_path('%<app_dir>s/feeds/%<year>d-personal-basic-checking.csv', year: year),
                     RRA::Fakers::FakeFeed.basic_checking(from: Date.new(year, 1, 1),
                                                          to: Date.new(year, 12, 31),
                                                          expense_descriptions: expense_descriptions,
                                                          income_descriptions: income_descriptions,
                                                          post_count: 300)
        end

        { warnings: [], errors: [] }
      end

      def initialize_transformers
        this_year.downto(this_year - 5).each do |year|

          File.write destination_path('%<app_dir>s/transformers/%<year>d-personal-basic-checking.yml',
                                      year: year),
                     RRA::Fakers::FakeTransformer.basic_checking(
                       label: format('Personal AcmeBank:Checking (%<year>s)', year: year),
                       input_path: format('%<year>d-personal-basic-checking.csv', year: year),
                       output_path: format('%<year>d-personal-basic-checking.journal', year: year)
                     )
        end

        { warnings: [], errors: [] }
      end

      def initialize_app
        { warnings: [], errors: [] }
      end

      def initialize_config
        { warnings: [], errors: [] }
      end

      def expense_descriptions
        @expense_descriptions ||= 1.upto(EXPENSE_DESCRIPTION_POOL_SIZE).map { Faker::Company.name }
      end

      def income_descriptions
        @expense_descriptions ||= 1.upto(INCOME_DESCRIPTION_POOL_SIZE).map { Faker::Company.name }
      end

      def this_year
        @this_year ||= Date.today.year
      end

      def destination_path(path, params = {})
        params[:app_dir] ||= app_dir
        format path, params
      end

      def project_journal_path
        destination_path '%<app_dir>s/%<project_name>s.journal',
                         project_name: project_name.downcase.tr(' ', '-')
      end
    end
  end
end
