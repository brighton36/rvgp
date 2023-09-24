# frozen_string_literal: true

require_relative '../plot'
require_relative '../plot/google-drive/sheet'
require_relative '../plot/google-drive/output_google_sheets'
require_relative '../plot/google-drive/output_csv'

module RRA
  module Commands
    # This class contains the handling of the 'publish_gsheets' command. This class
    # works very similar to the RRA::Commands:Plot command. Note that there is no
    # rake integration in this command, as that function is irrelevent to the notion
    # of an 'export'.
    class PublishGsheets < RRA::Base::Command
      DEFAULT_SLEEP_BETWEEN_SHEETS = 5

      accepts_options OPTION_ALL,
                      OPTION_LIST,
                      [:csvdir, :c, { has_value: 'DIRECTORY' }],
                      [:title,  :t, { has_value: 'TITLE' }],
                      [:sleep,  :s, { has_value: 'N' }]

      # This class represents a Google 'sheet', built from a Plot, available for
      # export to google. And dispatches a build request. Typically, the name of
      # a sheet is identical to the name of its corresponding plot. And, takes
      # the form of "#\\{year}-#\\{plotname}". See RRA::Base::Command::PlotTarget, from
      # which this class inherits, for a better representation of how this class
      # works.
      class Target < RRA::Base::Command::PlotTarget
        def to_sheet
          RRA::GoogleDrive::Sheet.new plot.title(name), plot.grid(name), { google: plot.google_options || {} }
        end
      end

      def initialize(*args)
        super(*args)

        options[:title] ||= 'RRA Finance Report %m/%d/%y %H:%M'
        options[:sleep] = options.key?(:sleep) ? options[:sleep].to_i : DEFAULT_SLEEP_BETWEEN_SHEETS

        if options.key? :csvdir
          unless File.writable? options[:csvdir]
            @errors << I18n.t('commands.publish_gsheets.errors.unable_to_write_to_csvdir', csvdir: options[:csvdir])
          end
        else
          @secrets_path = RRA.app.config.project_path('config/google-secrets.yml')

          unless File.readable?(@secrets_path)
            @errors << I18n.t('commands.publish_gsheets.errors.missing_google_secrets')
          end
        end
      end

      def execute!
        output = if options.key?(:csvdir)
                   RRA::GoogleDrive::ExportLocalCsvs.new(destination: options[:csvdir], format: 'csv')
                 else
                   RRA::GoogleDrive::ExportSheets.new(format: 'google_sheets',
                                                      title: options[:title],
                                                      secrets_file: @secrets_path)
                 end

        targets.each do |target|
          RRA.app.logger.info self.class.name, target.name do
            output.sheet target.to_sheet

            # NOTE: This should fix the complaints that google issues, from too many
            # requests per second.
            sleep options[:sleep] if output.is_a? RRA::GoogleDrive::ExportSheets

            {}
          end
        end
      end
    end
  end
end
