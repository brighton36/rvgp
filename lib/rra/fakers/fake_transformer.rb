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
          income: %<income>s
          expense: %<expense>s
        FEED_TEMPLATE

        # Generates a basic transformer, for use in transforming a basic_checking feed
        # @param from [String] The from parameter to write into our yaml
        # @param label [String] The label parameter to write into our yaml
        # @param format_path [String] A path to the format yaml, for use in the format parameter of our yaml
        # @param input_path [String] A path to the input feed, for use in the input parameter of our yaml
        # @param output_path [String] A path to the output journal, for use in the output parameter of our yaml
        # @param income [Array] An array of hashes, containing the income rules, to write into our yaml
        # @param expense [Array] An array of hashes, containing the expense rules, to write into our yaml
        # @return [String] A YAML file, containing the generated transformer
        def basic_checking(from: 'Personal:Assets:AcmeBank:Checking',
                           label: nil,
                           format_path: 'config/csv-format-acme-checking.yml',
                           input_path: nil,
                           output_path: nil,
                           income: nil,
                           expense: nil)

          raise StandardError if [from, label, format_path, input_path, output_path].any?(&:nil?)

          format BASIC_CHECKING_FEED,
                 from: from,
                 label: label,
                 format_path: format_path,
                 input_path: input_path,
                 output_path: output_path,
                 income: hashes_to_yaml_array(
                   [income, { match: '/.*/', to: 'Personal:Income:Unknown' }].flatten.compact
                 ),
                 expense: hashes_to_yaml_array(
                   [expense, { match: '/.*/', to: 'Personal:Expenses:Unknown' }].flatten.compact
                 )
        end

        private

        def hashes_to_yaml_array(hashes)
          format("\n%s", hashes.map do |hash|
            hash.each_with_index.map do |pair, i|
              (i.zero? ? '  - ' : '    ') + pair.join(': ')
            end
          end.flatten.join("\n"))
        end
      end
    end
  end
end
