# frozen_string_literal: true

require_relative 'faker_helpers'

module RRA
  module Fakers
    # Contains faker implementations that produce reconciler yamls
    class FakeReconciler < Faker::Base
      class << self
        include FakerHelpers

        # @!visibility private
        DEFAULT_FORMAT = <<~FORMAT_TEMPLATE
          csv_headers: true
          reverse_order: true
          default_currency: $
          fields:
            date: !!proc Date.strptime(row['Date'], '%m/%d/%Y')
            amount: !!proc >
              withdrawal, deposit = row[3..4].collect {|a| a.to_commodity unless a.empty?};
              ( deposit ? deposit.invert! : withdrawal ).quantity_as_s
            description: !!proc row['Description']
        FORMAT_TEMPLATE

        # @!visibility private
        BASIC_CHECKING_FEED = <<~FEED_TEMPLATE
          from: "%<from>s"
          label: "%<label>s"
          format: %<format>s
          input: %<input_path>s
          output: %<output_path>s
          balances:
            # TODO: Transcribe some expected balances, based off bank statements,
            # here, in the form :
            # '2023-01-04': $ 1000.00
          income: %<income>s
          expense: %<expense>s
        FEED_TEMPLATE

        # Generates a basic reconciler, for use in reconciling a basic_checking feed
        # @param from [String] The from parameter to write into our yaml
        # @param label [String] The label parameter to write into our yaml
        # @param format_path [String] A path to the format yaml, for use in the format parameter of our yaml
        # @param input_path [String] A path to the input feed, for use in the input parameter of our yaml
        # @param output_path [String] A path to the output journal, for use in the output parameter of our yaml
        # @param income [Array] An array of hashes, containing the income rules, to write into our yaml
        # @param expense [Array] An array of hashes, containing the expense rules, to write into our yaml
        # @return [String] A YAML file, containing the generated reconciler
        def basic_checking(from: 'Personal:Assets:AcmeBank:Checking',
                           label: nil,
                           format_path: nil,
                           input_path: nil,
                           output_path: nil,
                           income: nil,
                           expense: nil)

          raise StandardError if [from, label, input_path, output_path].any?(&:nil?)

          format = "!!include #{format_path}" if format_path
          format ||= format("\n%s", DEFAULT_FORMAT.gsub(/^/, '  ').chomp)

          format BASIC_CHECKING_FEED,
                 from: from,
                 label: label,
                 format: format,
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
