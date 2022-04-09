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

    options[:title] ||= "RRA Finance Report %m/%d/%y %H:%M"
    options[:sleep] = options.has_key?(:sleep) ? 
      options[:sleep].to_i : DEFAULT_SLEEP_BETWEEN_SHEETS

    if options.has_key? :csvdir
      @errors << I18n.t(
        'commands.publish_gsheets.errors.unable_to_write_to_csvdir', 
        csvdir: options[:csvdir]
      ) unless File.writable? options[:csvdir]
    else
      @secrets_path = RRA.app.config.project_path('config/google-secrets.yml')

      @errors << I18n.t(
        'commands.publish_gsheets.errors.missing_google_secrets'
      ) unless File.readable?(@secrets_path)
    end
  end

  def execute!
    output = options.has_key?(:csvdir) ?
      OutputCsv.new(destination: options[:csvdir], format: 'csv') :
      OutputGoogleSheets.new(format: 'google_sheets', title: options[:title],
        secrets_file: @secrets_path)

    targets.each do |target|
      RRA.app.logger.info self.class.name, target.name do 
        output.sheet target.to_sheet

        # NOTE: This should fix the complaints that google issues, from too many 
        # requests per second.
        sleep options[:sleep] if output.kind_of? OutputGoogleSheets

        {}
      end
    end
  end
end
