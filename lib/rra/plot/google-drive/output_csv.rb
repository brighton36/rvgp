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
      class ExportLocalCsvs
        attr_accessor :destination

        def initialize(options)
          unless [(options[:format] == 'csv'), File.directory?(options[:destination])].all?
            raise StandardError, 'Invalid Options, missing :destination'
          end

          @destination = options[:destination]
        end

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
