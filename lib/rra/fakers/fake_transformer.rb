
# frozen_string_literal: true

require_relative 'faker_helpers'

module RRA
  module Fakers
    # Contains faker implementations that produce transformer yamls
    class FakeTransformer < Faker::Base
      class << self
        include FakerHelpers

        BASIC_CHECKING_FEED = <<~FEED_TEMPLATE
          from: "%<from>s"
          label: "%<label>s"
          format: !!include %<format_path>s
          input: %<input_path>s
          output: %<output_path>s
          balances:
          income:
          - match: /.*/
            to: Personal:Income:Unknown
          expense:
          - match: /.*/
            to: Personal:Expenses:Unknown
        FEED_TEMPLATE

        # Generates a basic transformer, for use in transforming a basic_checking feed
        # @return [String] A YAML file, containing the generated transformer
        def basic_checking(from: 'Personal:Assets:AcmeBank:Checking',
                           label: nil,
                           format_path: 'config/csv-format-acme-checking.yml',
                           input_path: nil,
                           output_path: nil)

          # TODO: Generate documentation, and assert that require params are present

          format BASIC_CHECKING_FEED,
                 from: from, label: label, format_path: format_path,
                 input_path: input_path, output_path: output_path
        end
      end
    end
  end
end
