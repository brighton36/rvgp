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

        @skip_lines = yaml[:format][:skip_lines] || 0
        @trim_lines = yaml[:format][:trim_lines] || 0

        if yaml[:format].has_key? :csv_headers
          @csv_format = {headers: yaml[:format][:csv_headers]}
        end
      end
    end

    private

    # This takes the csv row, and uses the formatting config to return a hash
    # representation. Mostly we need this class to that the yaml can access a
    # named parameter, 'row'
    class RowTransformer
      attr_accessor :row
      def initialize(row); @row = row; end
      def [](k); k.respond_to?(:call) ? instance_eval(&k) : row[k]; end
    end

    def input_file_contents
      File.read(input_file).lines[skip_lines..(-1*(trim_lines+1))].join
    end

    # We actually returned semi-transformed transactions here. That lets us do
    # some remedial parsing before rule application, as well as reversing the order
    # which, is needed for the to_module to run in sequence.
    def source_postings
      @source_postings ||= begin 
        rows = CSV.parse input_file_contents, **csv_format
        rows.collect.with_index{ |csv_row, i| 
          row = RowTransformer.new csv_row

          # Set the object values, return the transformed row:
          tx = Hash[ fields_format.collect{ |k,v| [k.to_sym, row[v]] }.compact ]

          # Amount is a special case, which, we have now converted into 
          # commodity
          commodity = RRA::Journal::Commodity.from_symbol_and_amount(
            default_currency, tx[:amount])
          commodity.invert! if invert_amount

          RRA::TransformerBase::Posting.new i+1, date: tx[:date], 
            description: tx[:description], 
            commodity: transform_commodity(commodity), from: from
        }
      end
    end
  end
end
