# frozen_string_literal: true

require 'csv'
require_relative '../journal'

module RRA
  module Reconcilers
    class CsvReconciler < RRA::Base::Reconciler
      attr_reader :fields_format, :csv_format, :invert_amount, :skip_lines, :trim_lines

      def initialize(yaml)
        super yaml

        missing_fields = if yaml.key? :format
                           if yaml[:format].key?(:fields)
                             %i[date amount description].map do |attr|
                               format('format/fields/%s', attr) unless yaml[:format][:fields].key?(attr)
                             end.compact
                           else
                             ['format/fields']
                           end
                         else
                           ['format']
                         end

        raise MissingFields.new(*missing_fields) unless missing_fields.empty?

        @fields_format = yaml[:format][:fields] if yaml[:format].key? :fields
        @encoding_format = yaml[:format][:encoding] if yaml[:format].key? :encoding
        @invert_amount = yaml[:format][:invert_amount] || false if yaml[:format].key? :invert_amount
        @skip_lines = yaml[:format][:skip_lines]
        @trim_lines = yaml[:format][:trim_lines]
        @csv_format = { headers: yaml[:format][:csv_headers] } if yaml[:format].key? :csv_headers
      end

      class << self
        include RRA::Utilities

        # Mostly this is a class mathed, to make testing easier
        def input_file_contents(contents, skip_lines = nil, trim_lines = nil)
          start_offset = 0
          end_offset = contents.length

          if trim_lines
            trim_lines_regex = string_to_regex trim_lines.to_s
            trim_lines_regex ||= /(?:[^\n]*\n?){0,#{trim_lines}}\Z/m
            match = trim_lines_regex.match contents
            end_offset = match.begin 0 if match
            return String.new if end_offset.zero?
          end

          if skip_lines
            skip_lines_regex = string_to_regex skip_lines.to_s
            skip_lines_regex ||= /(?:[^\n]*\n){0,#{skip_lines}}/m
            match = skip_lines_regex.match contents
            start_offset = match.end 0 if match
          end

          # If our cursors overlapped, that means we're just returning an empty string
          return String.new if end_offset < start_offset

          contents[start_offset..(end_offset - 1)]
        end
      end

      private

      def input_file_contents
        open_args = {}
        open_args[:encoding] = @encoding_format if @encoding_format
        self.class.input_file_contents File.read(input_file, **open_args), skip_lines, trim_lines
      end

      # We actually returned semi-reconciled transactions here. That lets us do
      # some remedial parsing before rule application, as well as reversing the order
      # which, is needed for the to_shorthand to run in sequence.
      def source_postings
        @source_postings ||= begin
          rows = CSV.parse input_file_contents, **csv_format
          rows.collect.with_index do |csv_row, i|
            # Set the object values, return the reconciled row:
            tx = fields_format.collect do |field, formatter|
              # TODO: I think we can stick formatter as a key, if it's a string, or int
              [field.to_sym, formatter.respond_to?(:call) ? formatter.call(row: csv_row) : csv_row[field]]
            end.compact.to_h

            # Amount is a special case, which, we have now converted into
            # commodity
            if [RRA::Journal::ComplexCommodity, RRA::Journal::Commodity].any? { |klass| tx[:amount].is_a? klass }
              commodity = tx[:amount]
            end
            commodity ||= RRA::Journal::Commodity.from_symbol_and_amount(default_currency, tx[:amount])

            commodity.invert! if invert_amount

            RRA::Base::Reconciler::Posting.new i + 1,
                                               date: tx[:date],
                                               description: tx[:description],
                                               commodity: transform_commodity(commodity),
                                               from: from
          end
        end
      end
    end
  end
end
