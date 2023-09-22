# frozen_string_literal: true

require_relative '../fakers/fake_feed'
require_relative '../fakers/fake_transformer'

module RRA
  module Commands
    # This class handles the request to create a new RRA project.
    class NewProject < RRA::Base::Command
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
        %w[build feeds].each do |dir|
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

        # These are the app subdirectories...
        %w[commands grids plots transformers validations].each do |dir|
          full_dir = [app_dir, 'app', dir].join('/')
          next if Dir.exist? full_dir

          Dir.mkdir full_dir
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
          File.write destination_path('%<app_dir>s/feeds/%<year>d-personal-basic-checking.csv', year: year),
                     bank_feed(year)
        end

        { warnings: [], errors: [] }
      end

      def initialize_transformers
        each_year_in_project do |year|
          File.write destination_path('%<app_dir>s/app/transformers/%<year>d-personal-basic-checking.yml',
                                      year: year),
                     RRA::Fakers::FakeTransformer.basic_checking(
                       label: format('Personal AcmeBank:Checking (%<year>s)', year: year),
                       input_path: format('%<year>d-personal-basic-checking.csv', year: year),
                       output_path: format('%<year>d-personal-basic-checking.journal', year: year),
                       format_path: 'config/csv-format-acme-checking.yml',
                       income: [{ match: '/\AAmerican Express/', to: 'Personal:Liabilities:AmericanExpress' }] +
                               income_companies.map do |company|
                                 { 'match' => format('/%s/', company),
                                   'to' => format('Personal:Income:%s', company.tr('^a-zA-Z0-9', '')) }
                               end,
                       expense: [{ match: '/\AAmerican Express/', to: 'Personal:Liabilities:AmericanExpress' }] +
                                expense_companies.map do |company|
                                  # I don't know how else to explain these asset mitigating events. lol
                                  { match: format('/%s/', company), to: 'Personal:Expenses:Vices:Gambling' }
                                end +
                                monthly_expenses.keys.map do |category|
                                  { match: format('/%s/', company_for(category)), to: category }
                                end
                     )
        end

        { warnings: [], errors: [] }
      end

      def income_companies
        @income_companies ||= [Faker::Company.name]
      end

      def expense_companies
        @expense_companies ||= [Faker::Company.name]
      end

      def company_for(category)
        @company_for ||= {}
        @company_for[category] ||= Faker::Company.name
      end

      def monthly_expenses
        @monthly_expenses ||= {}.merge(
          # Rents go up every year:
          {
            'Personal:Expenses:Rent' => (0...num_months_in_project).map do |i|
              marginal_rent = RRA::Journal::Commodity.from_symbol_and_amount '$', (50 * (i / 12).floor)
              '$ 1800.00'.to_commodity + marginal_rent
            end
          },
          # Fixed monthly costs:
          {
            'Personal:Expenses:Gym': '$ 102.00',
            'Personal:Expenses:Phone': '$ 86.00'
          }.to_h do |cat, amnt|
            [cat.to_s, [amnt.to_commodity] * num_months_in_project]
          end,
          # Random-ish monthly Costs:
          {
            'Personal:Expenses:Food:Restaurants': { mean: 450, standard_deviation: 100 },
            'Personal:Expenses:Food:Groceries': { mean: 750, standard_deviation: 150 },
            'Personal:Expenses:DrugStores': { mean: 70, standard_deviation: 30 },
            'Personal:Expenses:Department Stores': { mean: 100, standard_deviation: 80 },
            'Personal:Expenses:Entertainment': { mean: 150, standard_deviation: 30 },
            'Personal:Expenses:Dating': { mean: 250, standard_deviation: 100 },
            'Personal:Expenses:Hobbies': { mean: 400, standard_deviation: 150 }
          }.to_h do |cat, num_opts|
            [cat.to_s,
             num_months_in_project.times.map do
               RRA::Journal::Commodity.from_symbol_and_amount '$', Faker::Number.normal(**num_opts).abs
             end]
          end,
          # 'Some months' Have these expenses.
          {
            'Personal:Expenses:Barber': { true_ratio: 0.75, mean: 50, standard_deviation: 10 },
            'Personal:Expenses:Charity': { true_ratio: 0.5, mean: 200, standard_deviation: 100 },
            'Personal:Expenses:Clothes': { true_ratio: 0.25, mean: 200, standard_deviation: 50 },
            'Personal:Expenses:Cooking Supplies': { true_ratio: 0.25, mean: 100, standard_deviation: 50 },
            'Personal:Expenses:Books': { true_ratio: 0.75, mean: 60, standard_deviation: 20 },
            'Personal:Expenses:Health:Dental': { true_ratio: 0.125, mean: 300, standard_deviation: 50 },
            'Personal:Expenses:Health:Doctor': { true_ratio: 0.0833, mean: 200, standard_deviation: 100 },
            'Personal:Expenses:Health:Medications': { true_ratio: 0.0833, mean: 40, standard_deviation: 50 },
            'Personal:Expenses:Home:Improvement': { true_ratio: 0.125, mean: 200, standard_deviation: 50 }
          }.map do |cat, opts|
            next unless Faker::Boolean.boolean true_ratio: opts.delete(:true_ratio)

            [cat.to_s,
             num_months_in_project.times.map do
               RRA::Journal::Commodity.from_symbol_and_amount '$', Faker::Number.normal(**opts).abs
             end]
          end.compact.to_h
        )
      end

      def bank_feed(year)
        @bank_feed ||= CSV.parse RRA::Fakers::FakeFeed.personal_checking(
          from: project_starts_on,
          to: today,
          expense_sources: expense_companies,
          income_sources: income_companies,
          opening_liability_balance: liabilities_at_month(-1),
          opening_asset_balance: assets_at_month(-1),
          monthly_expenses: monthly_expenses.transform_keys { |cat| company_for cat },
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
        @num_months_in_project ||= ((today.year * 12) + today.month) -
                                   ((project_starts_on.year * 12) +
                                    project_starts_on.month) + 1
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
