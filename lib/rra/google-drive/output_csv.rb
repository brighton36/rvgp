class OutputCsv
  attr_accessor :destination

  def initialize(options)
    raise StandardError, "Invalid Options, missing :destination" unless [ 
      (options[:format] == 'csv'), 
      File.directory?(options[:destination]) ].all?

    @destination = options[:destination]
  end

  def sheet(sheet)
    shortname = sheet.title.tr('^a-zA-Z0-9', '_').gsub(/_+/,'_').downcase.chomp('_')
    
    dest_csv = '%s/%s.csv' % [ destination.chomp('/'), shortname,'.csv' ]

    CSV.open(dest_csv, "wb") do |csv| 
      ([sheet.columns]+sheet.rows).each do |row|
        csv << row.collect{|c| (c.is_a? Date) ? c.strftime('%m/%d/%Y') : c }
      end
    end
  end
end

