#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'

require_relative '../lib/rvgp'

# Minitest class, used to test RVGP::Utilities::CsvReconciler
describe RVGP::Utilities::CsvObject do
  describe '.from_string' do
    let(:simple_csv) do
      <<~SIMPLE_CSV
        2025-01-01,Lawn Mower,$300.00
        2025-01-02,Gasoline,$10.00
      SIMPLE_CSV
    end

    let(:simple_header_csv) do
      <<~SIMPLE_HEADER_CSV
        date,description,amount
        2025-01-01,Lawn Mower,$300.00
        2025-01-02,Gasoline,$10.00
      SIMPLE_HEADER_CSV
    end

    it 'reads simple csv' do
      rows = RVGP::Utilities::CsvObject.from_string(simple_csv)
      expect(rows[0][0]).must_equal '2025-01-01'
      expect(rows[0][1]).must_equal 'Lawn Mower'
      expect(rows[0][2]).must_equal '$300.00'

      expect(rows[1][0]).must_equal '2025-01-02'
      expect(rows[1][1]).must_equal 'Gasoline'
      expect(rows[1][2]).must_equal '$10.00'
    end

    it 'reads simple header csv' do
      csv_file = Tempfile.open %w[rvgp_test .csv]
      csv_file.write(simple_header_csv)
      csv_file.close

      [[:from_file, csv_file.path], [:from_string, simple_header_csv]].each do |args|
        rows = RVGP::Utilities::CsvObject.send(*args, headers: true)

        expect(rows[0].date).must_equal '2025-01-01'
        expect(rows[0].description).must_equal 'Lawn Mower'
        expect(rows[0].amount).must_equal '$300.00'

        expect(rows[1].date).must_equal '2025-01-02'
        expect(rows[1].description).must_equal 'Gasoline'
        expect(rows[1].amount).must_equal '$10.00'
      end
    ensure
      csv_file.unlink
    end
  end
end
