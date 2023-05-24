require_relative 'rra/yaml'
require_relative 'rra/application'
require_relative 'rra/commands'
require_relative 'rra/transformer_base'

# NOTE: Transformers & modules may want to go into a registry system at
# some point, akin to grids/validations.
require_relative 'rra/transformers/csv_transformer'
require_relative 'rra/transformers/journal_transformer'
require_relative 'rra/transformer_modules/mortgage'
require_relative 'rra/transformer_modules/investment'
require_relative 'rra/transformer_modules/international_atm'

require_relative 'rra/validation_base'

require_relative 'rra/journal'
require_relative 'rra/ledger/ledger'
require_relative 'rra/hledger/hledger'

require_relative 'rra/grid_base'

# Gem Paths / Resources:
require_relative 'rra/gem'

I18n.load_path << Dir[RRA::Gem.root('resources/i18n/*.yml')]
RRA::Journal::Currency.currencies_config = RRA::Gem.root('resources/iso-4217-currencies.json')

# The base module, under which all RRA code is filed
module RRA
  def self.initialize_app(from_path)
    raise StandardError, 'Application is already initialized' if @app

    @app = Application.new from_path
  end

  def self.app
    @app
  end

  def self.pastel
    @pastel ||= Pastel.new enabled: $stdout.tty?
  end
end
