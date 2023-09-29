# frozen_string_literal: true

module RRA
  class Plot
    module GoogleDrive
      # This class is roughly, an kind of diagnostic alternative to RRA::GoogleDrive::ExportSheets,
      # which implements the :csvdir option of the RRA::Commands::PublishGsheets command.
      # Mostly, this object offers the methods that RRA::GoogleDrive::ExportSheets provides, and
      # writes the sheets that would have otherwise been published to google - into a
      # local directory, with csv files representing the Google sheet. This is mostly
      # a debugging and diagnostic function.
      # @attr_reader [String] destination The destination path, provided in the constructor
      class ExportLocalCsvs
        attr_accessor :destination

        # Output google-intentioned spreadsheet sheets, to csvs in a directory
        # @param [Hash] options The parameters governing this export
        # @option options [String] :format What format, to output the csvs in. Currently, The only supported value is
        #                                  'csv'.
        # @option options [String] :destination The path to a folder, to export sheets into
        def initialize(options)
          unless [(options[:format] == 'csv'), File.directory?(options[:destination])].all?
            raise StandardError, 'Invalid Options, missing :destination'
          end

          @destination = options[:destination]
        end

        # Ouput the provided sheet, into the destination path, as a csv
        # @param [RRA::Plot::GoogleDrive::Sheet] sheet The options, and data, for this sheet
        # @return [void]
        def sheet(sheet)
          shortname = sheet.title.tr('^a-zA-Z0-9', '_').gsub(/_+/, '_').downcase.chomp('_')

          CSV.open([destination.chomp('/'), '/', shortname, '.csv'].join, 'wb') do |csv|
            ([sheet.columns] + sheet.rows).each do |row|
              csv << row.map { |c| c.is_a?(Date) ? c.strftime('%m/%d/%Y') : c }
            end
          end
        end
      end
    end
  end
end
