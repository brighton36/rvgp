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

    describe ':sort_by' do
      it 'sorts simple csv' do
        rows = RVGP::Utilities::CsvObject.from_string(
          simple_header_csv,
          headers: true,
          sort_by: proc { |row| [row.amount] }
        )
        expect(rows[0].date).must_equal '2025-01-02'
        expect(rows[0].description).must_equal 'Gasoline'
        expect(rows[0].amount).must_equal '$10.00'

        expect(rows[1].date).must_equal '2025-01-01'
        expect(rows[1].description).must_equal 'Lawn Mower'
        expect(rows[1].amount).must_equal '$300.00'
      end
    end

    describe ':trim_lines and :strip_lines' do
      THREE_LINES = "Line 1\nLine 2\nLine 3\n"
      THREE_LINES_WO_ENDLINE = "Line 1\nLine 2\nLine 3"
      THREE_LINES_W_ENDLINE_AS_CHAR0 = "\nLine 2\nLine 3\n"

      it 'strips and trims' do
        assert_equal THREE_LINES, RVGP::Utilities::CsvObject.send(:skip_and_trim, THREE_LINES)
        assert_equal "Line 2\nLine 3\n", RVGP::Utilities::CsvObject.send(:skip_and_trim, THREE_LINES, skip_lines: 1)
        assert_equal "Line 3\n", RVGP::Utilities::CsvObject.send(:skip_and_trim, THREE_LINES, skip_lines: 2)
        assert_equal '', RVGP::Utilities::CsvObject.send(:skip_and_trim, THREE_LINES, skip_lines: 3)

        assert_equal "Line 1\nLine 2\n", RVGP::Utilities::CsvObject.send(:skip_and_trim, THREE_LINES, trim_lines: 1)
        assert_equal "Line 1\n", RVGP::Utilities::CsvObject.send(:skip_and_trim, THREE_LINES, trim_lines: 2)
        assert_equal '', RVGP::Utilities::CsvObject.send(:skip_and_trim, THREE_LINES, trim_lines: 3)

        assert_equal "Line 2\n", RVGP::Utilities::CsvObject.send(:skip_and_trim, THREE_LINES, skip_lines: 1, trim_lines: 1)
        assert_equal '', RVGP::Utilities::CsvObject.send(:skip_and_trim, THREE_LINES, skip_lines: 0, trim_lines: 3)
        assert_equal '', RVGP::Utilities::CsvObject.send(:skip_and_trim, THREE_LINES, trim_lines: 3)
        assert_equal '', RVGP::Utilities::CsvObject.send(:skip_and_trim, THREE_LINES, skip_lines: 3, trim_lines: 0)
        assert_equal '', RVGP::Utilities::CsvObject.send(:skip_and_trim, THREE_LINES, skip_lines: 3)
        assert_equal '', RVGP::Utilities::CsvObject.send(:skip_and_trim, THREE_LINES, skip_lines: 1, trim_lines: 2)
        assert_equal '', RVGP::Utilities::CsvObject.send(:skip_and_trim, THREE_LINES, skip_lines: 2, trim_lines: 1)

        # Test the case of the first line being empty
        assert_equal THREE_LINES_W_ENDLINE_AS_CHAR0, RVGP::Utilities::CsvObject.send(:skip_and_trim, THREE_LINES_W_ENDLINE_AS_CHAR0)

        assert_equal "Line 2\nLine 3\n", RVGP::Utilities::CsvObject.send(:skip_and_trim, THREE_LINES_W_ENDLINE_AS_CHAR0, skip_lines: 1)
        assert_equal "Line 3\n", RVGP::Utilities::CsvObject.send(:skip_and_trim, THREE_LINES_W_ENDLINE_AS_CHAR0, skip_lines: 2)
        assert_equal '', RVGP::Utilities::CsvObject.send(:skip_and_trim, THREE_LINES_W_ENDLINE_AS_CHAR0, skip_lines: 3)

        # Test to see what happens if we exceed the number of lines in the file
        assert_equal '', RVGP::Utilities::CsvObject.send(:skip_and_trim, THREE_LINES, skip_lines: 4, trim_lines: 1)
        assert_equal '', RVGP::Utilities::CsvObject.send(:skip_and_trim, THREE_LINES, skip_lines: 1, trim_lines: 4)
        assert_equal '', RVGP::Utilities::CsvObject.send(:skip_and_trim, THREE_LINES, skip_lines: 4)
        assert_equal '', RVGP::Utilities::CsvObject.send(:skip_and_trim, THREE_LINES, trim_lines: 4)
        assert_equal '', RVGP::Utilities::CsvObject.send(:skip_and_trim, THREE_LINES, skip_lines: 2, trim_lines: 2)

        # Test the case of more trims/skips than lines
        assert_equal THREE_LINES_WO_ENDLINE, RVGP::Utilities::CsvObject.send(:skip_and_trim, THREE_LINES_WO_ENDLINE)
        assert_equal "Line 1\nLine 2\n", RVGP::Utilities::CsvObject.send(:skip_and_trim, THREE_LINES_WO_ENDLINE, trim_lines: 1)

        assert_equal "Line 1\n", RVGP::Utilities::CsvObject.send(:skip_and_trim, THREE_LINES_WO_ENDLINE, trim_lines: 2)
        assert_equal '', RVGP::Utilities::CsvObject.send(:skip_and_trim, THREE_LINES_WO_ENDLINE, trim_lines: 3)
      end
    end
  end
end
