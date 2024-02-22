# frozen_string_literal: true

require_relative 'rra/utilities/yaml'
require_relative 'rra/application'
require_relative 'rra/commands'
require_relative 'rra/base/transformer'

# NOTE: Transformers & shorthand may want to go into a registry system at
# some point, akin to grids/validations.
require_relative 'rra/transformers/csv_transformer'
require_relative 'rra/transformers/journal_transformer'
require_relative 'rra/transformers/shorthand/mortgage'
require_relative 'rra/transformers/shorthand/investment'
require_relative 'rra/transformers/shorthand/international_atm'

require_relative 'rra/base/validation'

require_relative 'rra/journal'
require_relative 'rra/pta/ledger'
require_relative 'rra/pta/hledger'

require_relative 'rra/base/grid'

# Gem Paths / Resources:
require_relative 'rra/gem'

I18n.load_path << Dir[RRA::Gem.root('resources/i18n/*.yml')]
RRA::Journal::Currency.currencies_config = RRA::Gem.root('resources/iso-4217-currencies.json')

# The base module, under which all RRA code is filed
module RRA
  # @param from_path [String] The directory path, to an RRA project.
  # @return [RRA::Application] The initialized application, that was stored in RRA.app
  def self.initialize_app(from_path)
    raise StandardError, 'Application is already initialized' if @app

    @app = Application.new from_path
  end

  # @return [RRA::Application] The currently-initialized RRA:Application
  def self.app
    @app
  end

  # @return [Pastel] The global pastel object, used to output to the console.
  def self.pastel
    @pastel ||= Pastel.new enabled: $stdout.tty?
  end

  # @!attribute [r] self.commands
  #   Contains an array of all available objects, with parent of type {RRA::Base::Command}.
  #   @return [Array<RRA::Base::Command>] the commands that are available in this project
  # @!attribute [r] self.grids
  #   Contains an array of all available objects, with parent of type {RRA::Base::Grid}.
  #   @return [Array<RRA::Base::Grid>] the grids that are available in this project
  # @!attribute [r] self.journal_validations
  #   Contains an array of all available objects, with parent of type {RRA::Base::JournalValidation}.
  #   @return [Array<RRA::Base::JournalValidation>] the journal validations that are available in this project
  # @!attribute [r] self.system_validations
  #   Contains an array of all available objects, with parent of type {RRA::Base::SystemValidation}.
  #   @return [Array<RRA::Base::SystemValidation>] the system validations that are available in this project
end
