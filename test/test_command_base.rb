#!/usr/bin/env ruby

require "minitest/autorun"

require_relative '../lib/rra'

class TestCommandBase < Minitest::Test
  def test_remove_options_from_args

    options = [[:all, :a], [:list, :l], [:stdout, :s], 
      [:date, :d, {has_value: true}] ].collect{|args| 
        RRA::CommandBase::Option.new(*args) }

    assert_equal [{stdout: true}, ['target1', 'target2' ]],
      RRA::CommandBase::Option.remove_options_from_args(options, 
        ['--stdout', 'target1', 'target2'])
    assert_equal [{stdout: true}, ['target1', 'target2' ]],
      RRA::CommandBase::Option.remove_options_from_args(options,
        ['target1', '--stdout', 'target2'])
    assert_equal [{stdout: true}, ['target1', 'target2' ]],
      RRA::CommandBase::Option.remove_options_from_args(options, 
        ['target1',  'target2', '--stdout'])

    options << RRA::CommandBase::Option.new(:date, :d, {has_value: 'DATE'})

    assert_equal [{stdout: true, date: '2022-01-01'}, ['target1', 'target2']],
      RRA::CommandBase::Option.remove_options_from_args(options, 
        ['-d', '2022-01-01', 'target1', 'target2', '--stdout'])

    assert_equal [{stdout: true, date: '2022-01-01'}, ['target1', 'target2']],
      RRA::CommandBase::Option.remove_options_from_args(options, 
        ['target1', '--date', '2022-01-01', 'target2', '--stdout'])

    assert_equal [{stdout: true, date: '2022-01-01'}, ['target1', 'target2']],
      RRA::CommandBase::Option.remove_options_from_args(options, 
        ['target1', 'target2', '--date=2022-01-01', '--stdout'])

    assert_equal [{stdout: true, date: '2022-01-01'}, ['target1', 'target2']],
      RRA::CommandBase::Option.remove_options_from_args(options, 
        ['target1', 'target2', '--stdout', '-d', '2022-01-01' ])

    assert_equal [{stdout: true, date: '2022-01-01'}, ['target1', 'target2']],
      RRA::CommandBase::Option.remove_options_from_args(options, 
        ['--stdout', '--date', '2022-01-01', 'target1', 'target2' ])

    # This is just kind of an odd one, make sure we don't try to parse the
    # --random=arg as an option:
    assert_equal [{date: '2022-01-01'}, ['target1', 'target2', '--random=arg']],
      RRA::CommandBase::Option.remove_options_from_args(options, 
        ['--date', '2022-01-01', 'target1', 'target2', '--random=arg' ])

    # Note that date expects a value, yet, is at the end of the string:
    assert_raises RRA::CommandBase::Option::UnexpectedEndOfArgs do  
      RRA::CommandBase::Option.remove_options_from_args(options, 
        ['--stdout', 'target1', 'target2', '--date' ])
    end
  end
end
