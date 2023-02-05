#!/usr/bin/env ruby

require "minitest/autorun"

require_relative '../lib/rra'

class TestCsvTransformer < Minitest::Test
  THREE_LINES = "Line 1\nLine 2\nLine 3\n"
  THREE_LINES_WO_ENDLINE = "Line 1\nLine 2\nLine 3"
  THREE_LINES_W_ENDLINE_AS_CHAR0 = "\nLine 2\nLine 3\n"

  def test_input_file_contents
    assert_equal THREE_LINES, input_file_contents(THREE_LINES)
    assert_equal "Line 2\nLine 3\n", input_file_contents(THREE_LINES, 1)
    assert_equal "Line 3\n", input_file_contents(THREE_LINES, 2)
    assert_equal "", input_file_contents(THREE_LINES, 3)

    assert_equal "Line 1\nLine 2\n", input_file_contents(THREE_LINES, nil, 1)
    assert_equal "Line 1\n", input_file_contents(THREE_LINES, nil, 2)
    assert_equal "", input_file_contents(THREE_LINES, nil, 3)

    assert_equal "Line 2\n", input_file_contents(THREE_LINES, 1, 1)
    assert_equal "", input_file_contents(THREE_LINES, 0, 3)
    assert_equal "", input_file_contents(THREE_LINES, nil, 3)
    assert_equal "", input_file_contents(THREE_LINES, 3, 0)
    assert_equal "", input_file_contents(THREE_LINES, 3)
    assert_equal "", input_file_contents(THREE_LINES, 1, 2)
    assert_equal "", input_file_contents(THREE_LINES, 2, 1)

    # Test the case of the first line being empty
    assert_equal THREE_LINES_W_ENDLINE_AS_CHAR0, 
      input_file_contents(THREE_LINES_W_ENDLINE_AS_CHAR0)
      
    assert_equal "Line 2\nLine 3\n", input_file_contents(THREE_LINES_W_ENDLINE_AS_CHAR0, 1)
    assert_equal "Line 3\n", input_file_contents(THREE_LINES_W_ENDLINE_AS_CHAR0, 2)
    assert_equal "", input_file_contents(THREE_LINES_W_ENDLINE_AS_CHAR0, 3)

    # Test to see what happens if we exceed the number of lines in the file
    assert_equal "", input_file_contents(THREE_LINES, 4, 1)
    assert_equal "", input_file_contents(THREE_LINES, 1, 4)
    assert_equal "", input_file_contents(THREE_LINES, 4, nil)
    assert_equal "", input_file_contents(THREE_LINES, nil, 4)
    assert_equal "", input_file_contents(THREE_LINES, 2, 2)
 
    # Test the case of more trims/skips than lines
    assert_equal THREE_LINES_WO_ENDLINE, input_file_contents(THREE_LINES_WO_ENDLINE)
    assert_equal "Line 1\nLine 2\n", input_file_contents(THREE_LINES_WO_ENDLINE, nil, 1)

    assert_equal "Line 1\n", input_file_contents(THREE_LINES_WO_ENDLINE, nil, 2)
    assert_equal "", input_file_contents(THREE_LINES_WO_ENDLINE, nil, 3)
  end
  
  private

  # This is just to may the tests a bit easier to type
  def input_file_contents(*args)
    RRA::Transformers::CsvTransformer.input_file_contents(*args)
  end
end
