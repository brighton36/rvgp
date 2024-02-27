# frozen_string_literal: true

require_relative 'rvgp/utilities/yaml'
require_relative 'rvgp/application'
require_relative 'rvgp/commands'
require_relative 'rvgp/base/reconciler'

# NOTE: Reconcilers & shorthand may want to go into a registry system at
# some point, akin to grids/validations.
require_relative 'rvgp/reconcilers/csv_reconciler'
require_relative 'rvgp/reconcilers/journal_reconciler'
require_relative 'rvgp/reconcilers/shorthand/mortgage'
require_relative 'rvgp/reconcilers/shorthand/investment'
require_relative 'rvgp/reconcilers/shorthand/international_atm'

require_relative 'rvgp/base/validation'

require_relative 'rvgp/journal'
require_relative 'rvgp/pta/ledger'
require_relative 'rvgp/pta/hledger'

require_relative 'rvgp/base/grid'

# Gem Paths / Resources:
require_relative 'rvgp/gem'

I18n.load_path << Dir[RVGP::Gem.root('resources/i18n/*.yml')]
RVGP::Journal::Currency.currencies_config = RVGP::Gem.root('resources/iso-4217-currencies.json')

# The base module, under which all RVGP code is filed
module RVGP
  # @param from_path [String] The directory path, to an RVGP project.
  # @return [RVGP::Application] The initialized application, that was stored in RVGP.app
  def self.initialize_app(from_path)
    raise StandardError, 'Application is already initialized' if @app

    @app = Application.new from_path
  end

  # @return [RVGP::Application] The currently-initialized RVGP:Application
  def self.app
    @app
  end

  # @return [Pastel] The global pastel object, used to output to the console.
  def self.pastel
    @pastel ||= Pastel.new enabled: $stdout.tty?
  end

  # @!attribute [r] self.commands
  #   Contains an array of all available objects, with parent of type {RVGP::Base::Command}.
  #   @return [Array<RVGP::Base::Command>] the commands that are available in this project
  # @!attribute [r] self.grids
  #   Contains an array of all available objects, with parent of type {RVGP::Base::Grid}.<br>
  #   **NOTE:** RVGP.app.task_names => Array<String>, will return all grid-building tasks that have been defined in the
  #   project.
  #   @return [Array<RVGP::Base::Grid>] the grids that are available in this project
  # @!attribute [r] self.journal_validations
  #   Contains an array of all available objects, with parent of type {RVGP::Base::JournalValidation}.
  #   @return [Array<RVGP::Base::JournalValidation>] the journal validations that are available in this project
  # @!attribute [r] self.system_validations
  #   Contains an array of all available objects, with parent of type {RVGP::Base::SystemValidation}.<br>
  #   **NOTE:** RVGP.system_validations.task_names => Array<String>, will return all system validation tasks that have
  #   been defined in the project.
  #   @return [Array<RVGP::Base::SystemValidation>] the system validations that are available in this project
end
