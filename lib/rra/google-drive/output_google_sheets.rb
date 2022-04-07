require 'psych'

gem 'google-apis-sheets_v4'
require 'googleauth'
require "googleauth/stores/file_token_store"
require 'google/apis/sheets_v4'

class OutputGoogleSheets
  MSG_MISSING_SECRETS_FILE = "Missing required parameter :secrets_file"
  MSG_MISSING_SECRETS_PARAMS = "Config file is missing one or more of the required parameters: :client_id, :project_id, :client_secret, :token_path, :application_name"

  SV4 = Google::Apis::SheetsV4

  LOTUS_EPOCH = Date.new 1899, 12, 30

  COLOR_SCHEMES = [
    # Pink:  TODO : maybe remove this, or put into a palettes file/option
    [233, 29, 99, 255, 255, 255, 253, 220, 232]
  ]

  SCOPE = Google::Apis::SheetsV4::AUTH_SPREADSHEETS
  OOB_URI = "urn:ietf:wg:oauth:2.0:oob".freeze

  attr_reader :current_sheet_id, :spreadsheet_url

  def initialize(options)
    raise StandardError, MSG_MISSING_SECRETS_FILE unless options.has_key? :secrets_file

    config = Psych.load File.read(options[:secrets_file]), symbolize_names: true

    raise StandardError, MSG_MISSING_SECRETS_PARAMS unless %w(
      client_id project_id client_secret token_path application_name
    ).all?{|p| config.has_key? p.to_sym}

		@spreadsheet_title = options[:title]
    @service = SV4::SheetsService.new
    @service.client_options.log_http_requests = true if options[:log_http_requests]
    @client_id = Google::Auth::ClientId.from_hash( "installed" => {
      "client_id" => config[:client_id],
      "project_id" => config[:project_id],
      "client_secret" => config[:client_secret],
      "auth_uri" => "https://accounts.google.com/o/oauth2/auth",
      "token_uri" => "https://oauth2.googleapis.com/token",
      "auth_provider_x509_cert_url" => "https://www.googleapis.com/oauth2/v1/certs",
      "redirect_uris" => ["urn:ietf:wg:oauth:2.0:oob","http://localhost"]
    } )

    @token_store = Google::Auth::Stores::FileTokenStore.new file: config[:token_path]
    @application_name = config[:application_name]

    @service.client_options.application_name = @application_name
    @service.authorization = authorize

		@current_sheet_id = nil
		@now = Time.now
  end

  def authorize
    authorizer = Google::Auth::UserAuthorizer.new @client_id, SCOPE, @token_store
    user_id = "default"
    credentials = authorizer.get_credentials user_id
    if credentials.nil?
      # I'm a little fuzzy on some of this, since it's been a while since I've 
      # used this path
      url = authorizer.get_authorization_url base_url: OOB_URI
      puts "Open the following URL in the browser and enter the " \
           "resulting code after authorization:\n" + url
      code = gets
      credentials = authorizer.get_and_store_credentials_from_code(
        user_id: user_id, code: code, base_url: OOB_URI
      )
    end
    credentials
  end

	def spreadsheet_title
		@now.strftime @spreadsheet_title
	end

  # Create new spreadsheet object or return the existing one:
	def spreadsheet_id
		return @spreadsheet_id if @spreadsheet_id
  
    response = @service.create_spreadsheet( SV4::Spreadsheet.new( 
      properties: {title: spreadsheet_title} ) )

    @spreadsheet_url = response.spreadsheet_url
    @spreadsheet_id = response.spreadsheet_id
		@current_sheet_id = response.sheets[0].properties.sheet_id

    raise StandardError unless [@spreadsheet_id, @spreadsheet_url, @current_sheet_id].all?

    return @spreadsheet_id
  end

  def update_sheet_title!(sheet_id, title)
    update_sheet_properties_request = SV4::UpdateSheetPropertiesRequest.new(
      properties: {sheet_id: 0, title: title}, fields: 'title' )
		request_body = SV4::BatchUpdateSpreadsheetRequest.new(
      requests: [ SV4::Request.new(
          update_sheet_properties: update_sheet_properties_request 
        )]
      )

		response = @service.batch_update_spreadsheet spreadsheet_id, request_body

    raise StandardError, "Malformed response"  unless spreadsheet_id == response.spreadsheet_id
  end

  def band_rows(row_count, col_count)
    SV4::Request.new(
      add_banding: SV4::AddBandingRequest.new(
        banded_range: SV4::BandedRange.new(
          range: create_range(0,0, row_count, col_count),
          row_properties: band_scheme(0)
        ) ) )
  end

	def palettes_file_path
    # This has about 151 color palettes at the time of writing...
		File.expand_path File.dirname(__FILE__)+'/../color-palettes.yml'
  end

  def hex_to_rgb(hex)
    colors = hex.scan(/[0-9a-f]{#{hex.length == 6 ? 2 : 1}}/i).collect{|h| h.hex.to_f/255}
    SV4::Color.new red: colors[0], green: colors[1], blue: colors[2]
  end

  def band_scheme(number)
    hr, hg, hb, fr, fg, fb, sr, sg, sb = COLOR_SCHEMES[0]

    SV4::BandingProperties.new(
      header_color: SV4::Color.new(
        red: hr.to_f/255, green: hg.to_f/255, blue: hb.to_f/255),
      first_band_color: SV4::Color.new(
        red: fr.to_f/255, green: fg.to_f/255, blue: fb.to_f/255),
      second_band_color: SV4::Color.new(
        red: sr.to_f/255, green: sg.to_f/255, blue: sb.to_f/255) )
  end

  def add_sheet!(title)
    request_body = SV4::BatchUpdateSpreadsheetRequest.new(
      requests: [ SV4::Request.new(  add_sheet: SV4::AddSheetRequest.new( 
         properties: {title: title}) )]
    )

    response = @service.batch_update_spreadsheet spreadsheet_id, request_body

    raise StandardError, "Invalid sheet index" unless [
      (response.replies[0].add_sheet.properties.title), 
      (response.replies[0].add_sheet.properties.sheet_id),
      (response.replies[0].add_sheet.properties.title == title) ].all?

    @current_sheet_id = response.replies[0].add_sheet.properties.sheet_id
  end

  def update_spreadsheet_value!(sheet_title, values)
    range_name = ['%s!A1:%s%d' % [sheet_title, (values[0].length+64).chr, 
      values.count] ]

    # We do this because dates are a pita, and are easier to send as floats
    values_transformed = values.collect{|row|
      row.collect{|c| (c.is_a? Date) ? (c - LOTUS_EPOCH).to_f : c } }

    response = @service.update_spreadsheet_value(spreadsheet_id, range_name,
      SV4::ValueRange.new(values: values_transformed), value_input_option:'RAW')

    raise StandardError, "Not all cells were updated" unless [ 
      (response.updated_cells == values_transformed.flatten.reject(&:nil?).count), 
      (response.updated_rows == values_transformed.count), 
      (response.updated_columns == values_transformed.max_by(&:length).length)].all?
  end

  def create_range(start_row = 0, start_col = 0, end_row = nil, end_col = nil)
    SV4::GridRange.new( sheet_id: current_sheet_id, 
      start_row_index: start_row,
      start_column_index: start_col, 
      end_row_index: end_row || (start_row+1), 
      end_column_index: end_col || (start_col+1) )
  end

  def update_column_width(col_start, col_end, width)
    SV4::Request.new(  
      update_dimension_properties: SV4::UpdateDimensionPropertiesRequest.new(
      range: { sheet_id: current_sheet_id,  dimension: "COLUMNS",
        start_index: col_start, end_index: col_end},
      fields: 'pixelSize',
      properties: SV4::DimensionProperties.new(pixel_size: width), 
    ) ) 
  end

  def repeat_cell(range, fields, cell)
    { repeat_cell: { range: range, fields: fields, cell: cell } }
  end

  def batch_update_spreadsheet!(requests, skip_serialization = false)
    # Seems like there a bug in the BatchUpdateSpreadsheetRequest::Reflection
    # that is preventing the api from serializing the 'cell' key. I think that
    # the word is a reserved word in the reflection api...
    # Nonetheless, the manual approach works with skip_serialization enabled.
    #
    request_body = { requests: requests }

    @service.batch_update_spreadsheet spreadsheet_id, 
      (skip_serialization) ? request_body.to_h.to_json : request_body, 
      options: {skip_serialization: skip_serialization}
  end

  def sheet(sheet)
    raise StandardError, "Too many columns..." if sheet.columns.length > 26
    raise StandardError, "No header..." if sheet.columns.length == 0

    # Create a sheet, or update the sheet 0 title:
    if current_sheet_id.nil?
      update_sheet_title! 0, sheet.title
    else
      add_sheet! sheet.title
    end

    # Now that we have a title and sheet id, we can insert the data:
    update_spreadsheet_value! sheet.title, [sheet.columns]+sheet.rows

    # Format the sheet:
    batch_update_spreadsheet! [
      # Set the Date column:
      repeat_cell( create_range(1, 0, sheet.rows.count+1), 
        'userEnteredFormat.numberFormat',
        {userEnteredFormat: {numberFormat: {type: 'DATE', pattern: 'mm/dd/yy'}}} ),
      # Set the Money columns:
      repeat_cell( create_range(1, 1, sheet.rows.count+1, sheet.columns.count), 
        'userEnteredFormat.numberFormat',
        {userEnteredFormat: {numberFormat: {type: 'CURRENCY', pattern: '"$"#,##0.00'}}} ),
      # Format the header row text:
      repeat_cell( create_range(0, 0, 1, sheet.columns.count), 
        'userEnteredFormat(textFormat,horizontalAlignment)',
        {userEnteredFormat: {textFormat: {bold: true}, horizontalAlignment: 'CENTER'}} ),
      # Color-band the rows:
      band_rows(sheet.rows.count+1, sheet.columns.count),
      # Resize the series columns:
      update_column_width(1, sheet.columns.count, 70)
    ], true

    # Add a chart!
    add_chart! sheet
  end

	def add_chart!(sheet)
    stacked_type = nil

    if sheet.options.key?(:google)
      gparams = sheet.options[:google]
      series_colors = gparams[:series_colors] 
      series_types = gparams[:series_types] 
      default_series_type = gparams[:default_series_type]
      series_line_styles = gparams[:series_line_styles]
      chart_type = (gparams[:chart_type]) ? gparams[:chart_type].to_s.upcase : nil
      stacked_type = gparams[:stacked_type] if gparams[:stacked_type]

      axis = gparams[:axis].collect{|position, title|
        SV4::BasicChartAxis.new position: '%s_AXIS' % position.to_s.upcase,
          title: title 
      } if gparams.has_key? :axis

      series_target_axis = gparams[:series_target_axis]
    end

    series = (1...sheet.columns.count).collect{|i|
      series_params = {
        targetAxis: '%s_AXIS' % (series_target_axis || :left).to_s.upcase,
        series: {
          sourceRange: {
            sources: [ create_range(0, i, sheet.rows.count+1, i+1) ]
          } 
        } }
  
      if series_colors and sheet.columns[i]
        color = series_colors[sheet.columns[i].to_sym]
        series_params[:color] = hex_to_rgb(color) if color
      end

      if series_line_styles
        style = series_line_styles[sheet.columns[i].to_sym]
        series_params[:lineStyle] = SV4::LineStyle.new(
          type: 'MEDIUM_DASHED') if style == 'dashed'
      end

      if series_types
        type = series_types[sheet.columns[i]]
        series_params[:type] = type ? type : default_series_type
      end

      series_params
    }

		request_body = [ 
      { addChart: {
        chart: {
          position: {newSheet: true},
          spec: {
            title: sheet.title,
            basicChart: {
              headerCount: 1,
              chartType: chart_type || 'LINE',
              legendPosition: 'RIGHT_LEGEND',
              stackedType: stacked_type,
              domains: [ {
                domain: {
                  sourceRange: { 
                    sources: [ create_range(0,0, sheet.rows.count+1) ] 
                  }
                }
              } ],
              series: series
            }
          } 
        } 
      } 
    } ]

    response = batch_update_spreadsheet! request_body, true

		chart_sheet_id = response.replies[0].add_chart.chart.position.sheet_id

    raise StandardError, "Error Creating Chart"  unless chart_sheet_id

    # Rename the new chart tab name to match the title:
    request_body = SV4::BatchUpdateSpreadsheetRequest.new(
      requests: [ SV4::Request.new(  
        update_sheet_properties: SV4::UpdateSheetPropertiesRequest.new(
           properties: SV4::SheetProperties.new(
             sheet_id: chart_sheet_id, 
             title: '%s (Chart)' % sheet.title), 
          fields: 'title',
        ) ) 
      ] )
		response = @service.batch_update_spreadsheet spreadsheet_id, request_body

    raise StandardError, "Malformed response"  unless spreadsheet_id == response.spreadsheet_id
	end

end
