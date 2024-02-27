# frozen_string_literal: true

require_relative '../plot'
require_relative '../plot/google-drive/sheet'
require_relative '../plot/google-drive/output_google_sheets'
require_relative '../plot/google-drive/output_csv'

module RVGP
  module Commands
    # @!visibility private
    # This class contains the handling of the 'publish_gsheets' command. This class
    # works very similar to the RVGP::Commands:Plot command. Note that there is no
    # rake integration in this command, as that function is irrelevent to the notion
    # of an 'export'.
    class PublishGsheets < RVGP::Base::Command
      # @!visibility private
      DEFAULT_SLEEP_BETWEEN_SHEETS = 5

      accepts_options OPTION_ALL,
                      OPTION_LIST,
                      [:csvdir, :c, { has_value: 'DIRECTORY' }],
                      [:title,  :t, { has_value: 'TITLE' }],
                      [:sleep,  :s, { has_value: 'N' }]

      # @!visibility private
      # This class represents a Google 'sheet', built from a Plot, available for
      # export to google. And dispatches a build request. Typically, the name of
      # a sheet is identical to the name of its corresponding plot. And, takes
      # the form of "#\\{year}-#\\{plotname}". See RVGP::Base::Command::PlotTarget, from
      # which this class inherits, for a better representation of how this class
      # works.
      class Target < RVGP::Base::Command::PlotTarget
        # @!visibility private
        def to_sheet
          RVGP::Plot::GoogleDrive::Sheet.new plot.title(name), plot.grid(name), { google: plot.google_options || {} }
        end
      end

      # @!visibility private
      def initialize(*args)
        super(*args)

        options[:title] ||= 'RVGP Finance Report %m/%d/%y %H:%M'
        options[:sleep] = options.key?(:sleep) ? options[:sleep].to_i : DEFAULT_SLEEP_BETWEEN_SHEETS

        if options.key? :csvdir
          unless File.writable? options[:csvdir]
            @errors << I18n.t('commands.publish_gsheets.errors.unable_to_write_to_csvdir', csvdir: options[:csvdir])
          end
        else
          @secrets_path = RVGP.app.config.project_path('config/google-secrets.yml')

          unless File.readable?(@secrets_path)
            @errors << I18n.t('commands.publish_gsheets.errors.missing_google_secrets')
          end
        end
      end

      # @!visibility private
      def execute!
        output = if options.key?(:csvdir)
                   RVGP::Plot::GoogleDrive::ExportLocalCsvs.new(destination: options[:csvdir], format: 'csv')
                 else
                   RVGP::Plot::GoogleDrive::ExportSheets.new(format: 'google_sheets',
                                                       title: options[:title],
                                                       secrets_file: @secrets_path)
                 end

        targets.each do |target|
          RVGP.app.logger.info self.class.name, target.name do
            output.sheet target.to_sheet

            # NOTE: This should fix the complaints that google issues, from too many
            # requests per second.
            sleep options[:sleep] if output.is_a? RVGP::Plot::GoogleDrive::ExportSheets

            {}
          end
        end
      end
    end
  end
end
