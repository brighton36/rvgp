require 'csv'
require_relative '../journal'

module RRA::Transformers
  class CsvTransformer < RRA::TransformerBase
    attr_reader :fields_format, :csv_format, :invert_amount, :skip_lines,
      :trim_lines

    def initialize(yaml)
      super yaml

      if yaml.has_key? :format
        if yaml[:format].has_key? :fields
          @fields_format = yaml[:format][:fields]
        end

        if yaml[:format].has_key? :invert_amount
          @invert_amount = yaml[:format][:invert_amount] || false
        end

        @skip_lines = yaml[:format][:skip_lines]
        @trim_lines = yaml[:format][:trim_lines]

        if yaml[:format].has_key? :csv_headers
          @csv_format = {headers: yaml[:format][:csv_headers]}
        end
      end
    end

    class << self
      include RRA::Utilities

      # Mostly this is a class mathed, to make testing easier
      def input_file_contents(contents, skip_lines = nil, trim_lines = nil)
        start_offset = 0
        end_offset = contents.length
        
        if trim_lines
          trim_lines_regex = string_to_regex trim_lines.to_s
          trim_lines_regex = /(?:[^\n]*[\n]?){0,#{trim_lines}}\Z/m unless trim_lines_regex
          match = trim_lines_regex.match contents
          end_offset = match.begin 0 if match
          return String.new if end_offset == 0
        end

        if skip_lines
          skip_lines_regex = string_to_regex skip_lines.to_s
          skip_lines_regex = /(?:[^\n]*\n){0,#{skip_lines}}/m unless skip_lines_regex
          match = skip_lines_regex.match contents
          start_offset = match.end 0 if match
        end

        # If our cursors overlapped, that means we're just returning an empty string
        return String.new if end_offset < start_offset

        contents[start_offset..(end_offset-1)]
      end
    end

    private

    def input_file_contents
      self.class.input_file_contents File.read(input_file), skip_lines, trim_lines
    end

    # We actually returned semi-transformed transactions here. That lets us do
    # some remedial parsing before rule application, as well as reversing the order
    # which, is needed for the to_module to run in sequence.
    def source_postings
      @source_postings ||= begin 
        rows = CSV.parse input_file_contents, **csv_format
        rows.collect.with_index{ |csv_row, i| 
          # Set the object values, return the transformed row:
          tx = Hash[ fields_format.collect{ |field, formatter| 
            [ field.to_sym, formatter.respond_to?(:call) ? 
                formatter.call(row: csv_row) : csv_row[field] ] 
          }.compact ]

          # Amount is a special case, which, we have now converted into 
          # commodity
          commodity = (
            if tx[:amount].kind_of?(RRA::Journal::ComplexCommodity)
              tx[:amount] 
            elsif tx[:amount].kind_of?(RRA::Journal::Commodity)
              tx[:amount] 
            else
              RRA::Journal::Commodity.from_symbol_and_amount(default_currency, tx[:amount])
            end
          )

          commodity.invert! if invert_amount 

          RRA::TransformerBase::Posting.new i+1, date: tx[:date], 
            description: tx[:description], 
            commodity: transform_commodity(commodity), from: from
        }
      end
    end
  end
end
