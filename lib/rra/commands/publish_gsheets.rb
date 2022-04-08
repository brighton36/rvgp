require 'rra/plot'
require 'rra/google-drive/sheet'
require 'rra/google-drive/output_google_sheets'
require 'rra/google-drive/output_csv'

class RRA::Commands::PublishGsheets < RRA::CommandBase
  DEFAULT_SLEEP_BETWEEN_SHEETS = 5

  accepts_options OPTION_ALL, OPTION_LIST, 
    [:csvdir, :c, {has_value: 'DIRECTORY'}],
    [:title,  :t, {has_value: 'TITLE'}],
    [:sleep,  :s, {has_value: 'N'}]

  class Target < RRA::CommandBase::PlotTarget
    def to_sheet
      Sheet.new plot.title(name), plot.grid(name),
        { google: plot.google_options ? plot.google_options : {} }
    end
  end

  def initialize(*args)
    super *args
  end

  def execute!
    # TODO: Move this into an initialize
    title = options.has_key?(:title) ? 
      options[:title] : "RRA Finance Report %m/%d/%y %H:%M"

    sleep_seconds = options.has_key?(:sleep) ? 
      options[:sleep].to_i : DEFAULT_SLEEP_BETWEEN_SHEETS

    output = if options.has_key? :csvdir
      # TODO: I18n
      raise StandardError, "Unable to write to path \"%s\"" % [
        options[:csvdir] ] unless File.writable? options[:csvdir]

      OutputCsv.new destination: options[:csvdir], format: 'csv'
    else
      secrets_path = RRA.app.config.project_path('config/google-secrets.yml')

      # TODO: I18n
      raise StandardError, 
        "Missing a config/google-secrets.yml file in your project directory" unless (
          File.readable?(secrets_path) )

      OutputGoogleSheets.new format: 'google_sheets', title: title,
        secrets_file: secrets_path
    end

    targets.each do |target|
      RRA.app.logger.info self.class.name, target.name do 
        output.sheet target.to_sheet

        # NOTE: This should fix the complaints that google issues, from too many 
        # requests per second.
        sleep sleep_seconds if output.kind_of? OutputGoogleSheets

        {}
      end
    end
  end
end
