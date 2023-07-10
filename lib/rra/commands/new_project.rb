# frozen_string_literal: true

require_relative '../fakers/fake_feed'
require_relative '../fakers/fake_transformer'

module RRA
  module Commands
    # This class handles the request to create a new RRA project.
    class NewProject < RRA::CommandBase
      PROJECT_FILE = <<~END_OF_PROJECT_FILE
        # vim:filetype=ledger

        # Unautomated journals:
        include journals/*.journal

        # Reconciled journals:
        include build/journals/*.journal

        # Local Variables:
        # project_name: "%<project_name>s"
        # End:
      END_OF_PROJECT_FILE

      OPENING_BALANCES_FILE = <<~END_OF_BALANCES_FILE
        2017/12/31 Opening Balances
          Personal:Liabilities:AmericanExpress              %<liabilities>s
          Personal:Equity:Opening Balances:AmericanExpress

        2017/12/31 Opening Balances
          Personal:Assets:AcmeBank:Checking                 %<assets>s
          Personal:Equity:Opening Balances:AcmeBank
      END_OF_BALANCES_FILE

      EXPENSE_CATEGORIES = [
        'Personal:Expenses:Rent',
        'Personal:Expenses:Food:Restaurants',
        'Personal:Expenses:Food:Groceries',
        'Personal:Expenses:Drug Stores',
        'Personal:Expenses:Phone',
        'Personal:Expenses:Barber',
        'Personal:Expenses:Charity',
        'Personal:Expenses:Clothes',
        'Personal:Expenses:Cooking Supplies',
        'Personal:Expenses:Department Stores',
        'Personal:Expenses:Books',
        'Personal:Expenses:Entertainment',
        'Personal:Expenses:Dating',
        'Personal:Expenses:Gym',
        'Personal:Expenses:Hobbies',
        'Personal:Expenses:Health:Dental',
        'Personal:Expenses:Health:Doctor',
        'Personal:Expenses:Health:Medications',
        'Personal:Expenses:Home:Improvement'
      ].freeze
      EXPENSE_COMPANY_SIZE = EXPENSE_CATEGORIES.length * 3
      INCOME_COMPANY_SIZE = 2

      YEARS_IN_NEW_PROJECT = 5

      attr_reader :errors, :app_dir, :project_name

      # We don't call super, mostly because this command needs to run in absence
      # of an initialized project directory. This makes this command unique
      # amongst the rest of the commands....
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
        %i[project_directory bank_feeds transformers].each do |step|
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
        %w[build feeds transformers].each do |dir|
          full_dir = [app_dir, dir].join('/')
          if Dir.exist? full_dir
            @warnings << [I18n.t('commands.new_project.errors.directory_exists', dir: full_dir)]
          else
            Dir.mkdir full_dir
          end
        end

        Dir.glob(RRA::Gem.root('resources/skel/*')) do |filename|
          FileUtils.cp_r filename, app_dir
        end

        # Main project journal:
        File.write project_journal_path,
                   format(PROJECT_FILE, project_name: @project_name.gsub('"', '\\"'))

        # Opening Balances journal:
        File.write destination_path('%<app_dir>s/journals/opening-balances.journal'),
                   format(OPENING_BALANCES_FILE,
                          liabilities: liabilities_at_month(-1).invert!.to_s(precision: 2),
                          assets: assets_at_month(-1).to_s(precision: 2))

        { warnings: @warnings, errors: [] }
      end

      def initialize_bank_feeds
        each_year_in_project do |year|
          # entries = liability_payments.select { |e| e['Date'].year == year }
          File.write destination_path('%<app_dir>s/feeds/%<year>d-personal-basic-checking.csv', year: year),
                     bank_feed(year)
        end

        { warnings: [], errors: [] }
      end

      def initialize_transformers
        incomes = income_companies.map do |company|
          { 'match' => format('/%s/', company),
            'to' => format('Personal:Income:%s', company.tr('^a-zA-Z0-9', '')) }
        end

        incomes << { match: '/\AAmerican Express/', to: 'Personal:Liabilities:AmericanExpress' }

        run_length = EXPENSE_COMPANY_SIZE / EXPENSE_CATEGORIES.length

        expenses = EXPENSE_CATEGORIES.each_with_index.map do |category, i|
          start_i = i * run_length
          end_i = ((i + 1) * run_length) - 1
          match = format '/(?:%s)/', (start_i..end_i).map { |j| expense_companies[j] }.join('|')
          { match: match, to: category }
        end

        # Add the liability payout to expenses:
        expenses << { match: '/\AAmerican Express/', to: 'Personal:Liabilities:AmericanExpress' }

        each_year_in_project do |year|
          File.write destination_path('%<app_dir>s/transformers/%<year>d-personal-basic-checking.yml',
                                      year: year),
                     RRA::Fakers::FakeTransformer.basic_checking(
                       label: format('Personal AcmeBank:Checking (%<year>s)', year: year),
                       input_path: format('%<year>d-personal-basic-checking.csv', year: year),
                       output_path: format('%<year>d-personal-basic-checking.journal', year: year),
                       format_path: 'config/csv-format-acme-checking.yml',
                       income: incomes,
                       expense: expenses
                     )
        end

        { warnings: [], errors: [] }
      end

      def income_companies
        @income_companies ||= INCOME_COMPANY_SIZE.times.map { Faker::Company.name }
      end

      def expense_companies
        @expense_companies ||= 1.upto(EXPENSE_COMPANY_SIZE).map { Faker::Company.name }
      end

      def bank_feed(year)
        # TODO: we still need to specify expense categories in a better format...
        @bank_feed ||= CSV.parse RRA::Fakers::FakeFeed.personal_checking(
          from: project_starts_on,
          to: today,
          expense_sources: expense_companies,
          income_sources: income_companies,
          opening_liability_balance: liabilities_at_month(-1),
          opening_asset_balance: assets_at_month(-1),
          liability_sources: ['American Express'],
          liabilities_by_month: (0...num_months_in_project).map { |i| liabilities_at_month i },
          assets_by_month: (0...num_months_in_project).map { |i| assets_at_month i }
        ), headers: true

        CSV.generate headers: @bank_feed.headers, write_headers: true do |csv|
          @bank_feed.each { |row| csv << row if Date.strptime(row['Date'], '%m/%d/%Y').year == year }
        end
      end

      def today
        @today ||= Date.today
      end

      def project_starts_on
        @project_starts_on ||= Date.new(today.year - YEARS_IN_NEW_PROJECT, 1, 1)
      end

      def num_months_in_project
        @num_months_in_project ||= ((today.year * 12) + today.month) - ((project_starts_on.year * 12) + project_starts_on.month) + 1
      end

      def each_year_in_project(&block)
        today.year.downto(today.year - YEARS_IN_NEW_PROJECT).each(&block)
      end

      def destination_path(path, params = {})
        params[:app_dir] ||= app_dir
        format path, params
      end

      def liabilities_at_month(num)
        # I played with this until it offered a nice contrast with the assets curve
        RRA::Journal::Commodity.from_symbol_and_amount('$',
                                                        (Math.sin((num.to_f + 40) / 24) * 30_000) + 30_000)
      end

      def assets_at_month(num)
        # This just happened to be an interesting graph... to me:
        RRA::Journal::Commodity.from_symbol_and_amount('$',
                                                       (Math.sin((num.to_f - 32) / 20) * 40_000) + 50_000)
      end

      def project_journal_path
        destination_path '%<app_dir>s/%<project_name>s.journal',
                         project_name: project_name.downcase.tr(' ', '-')
      end
    end
  end
end
