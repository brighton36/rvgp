#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'

require_relative '../lib/rvgp'

# Minitest class, used to test RVGP::Reconcilers::CsvReconciler
class TestCsvReconciler < Minitest::Test
  THREE_LINES = "Line 1\nLine 2\nLine 3\n"
  THREE_LINES_WO_ENDLINE = "Line 1\nLine 2\nLine 3"
  THREE_LINES_W_ENDLINE_AS_CHAR0 = "\nLine 2\nLine 3\n"

  def test_path_to_rows
    assert_equal THREE_LINES, path_to_rows(THREE_LINES)
    assert_equal "Line 2\nLine 3\n", path_to_rows(THREE_LINES, skip_lines: 1)
    assert_equal "Line 3\n", path_to_rows(THREE_LINES, skip_lines: 2)
    assert_equal '', path_to_rows(THREE_LINES, skip_lines: 3)

    assert_equal "Line 1\nLine 2\n", path_to_rows(THREE_LINES, trim_lines: 1)
    assert_equal "Line 1\n", path_to_rows(THREE_LINES, trim_lines: 2)
    assert_equal '', path_to_rows(THREE_LINES, trim_lines: 3)

    assert_equal "Line 2\n", path_to_rows(THREE_LINES, skip_lines: 1, trim_lines: 1)
    assert_equal '', path_to_rows(THREE_LINES, skip_lines: 0, trim_lines: 3)
    assert_equal '', path_to_rows(THREE_LINES, trim_lines: 3)
    assert_equal '', path_to_rows(THREE_LINES, skip_lines: 3, trim_lines: 0)
    assert_equal '', path_to_rows(THREE_LINES, skip_lines: 3)
    assert_equal '', path_to_rows(THREE_LINES, skip_lines: 1, trim_lines: 2)
    assert_equal '', path_to_rows(THREE_LINES, skip_lines: 2, trim_lines: 1)

    # Test the case of the first line being empty
    assert_equal THREE_LINES_W_ENDLINE_AS_CHAR0, path_to_rows(THREE_LINES_W_ENDLINE_AS_CHAR0)

    assert_equal "Line 2\nLine 3\n", path_to_rows(THREE_LINES_W_ENDLINE_AS_CHAR0, skip_lines: 1)
    assert_equal "Line 3\n", path_to_rows(THREE_LINES_W_ENDLINE_AS_CHAR0, skip_lines: 2)
    assert_equal '', path_to_rows(THREE_LINES_W_ENDLINE_AS_CHAR0, skip_lines: 3)

    # Test to see what happens if we exceed the number of lines in the file
    assert_equal '', path_to_rows(THREE_LINES, skip_lines: 4, trim_lines: 1)
    assert_equal '', path_to_rows(THREE_LINES, skip_lines: 1, trim_lines: 4)
    assert_equal '', path_to_rows(THREE_LINES, skip_lines: 4)
    assert_equal '', path_to_rows(THREE_LINES, trim_lines: 4)
    assert_equal '', path_to_rows(THREE_LINES, skip_lines: 2, trim_lines: 2)

    # Test the case of more trims/skips than lines
    assert_equal THREE_LINES_WO_ENDLINE, path_to_rows(THREE_LINES_WO_ENDLINE)
    assert_equal "Line 1\nLine 2\n", path_to_rows(THREE_LINES_WO_ENDLINE, trim_lines: 1)

    assert_equal "Line 1\n", path_to_rows(THREE_LINES_WO_ENDLINE, trim_lines: 2)
    assert_equal '', path_to_rows(THREE_LINES_WO_ENDLINE, trim_lines: 3)
  end

  private

  # This is just to may the tests a bit easier to type
  def path_to_rows(contents, *args)
    # TODO : I broke this when I refactored... come back and fix this at some point when I
    # figure out what this wants to be...
    RVGP::Reconcilers::CsvReconciler.path_to_rows(*args)
  end
end
