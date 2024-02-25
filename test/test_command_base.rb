#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'

require_relative '../lib/rvgp'

# Minitest class, used to test RVGP::Base::Command
class TestBaseCommand < Minitest::Test
  def test_remove_options_from_args
    options = [%i[all a], %i[list l], %i[stdout s], [:date, :d, { has_value: true }]].map do |args|
      RVGP::Base::Command::Option.new(*args)
    end

    assert_equal [{ stdout: true }, %w[target1 target2]],
                 RVGP::Base::Command::Option.remove_options_from_args(options, ['--stdout', 'target1', 'target2'])
    assert_equal [{ stdout: true }, %w[target1 target2]],
                 RVGP::Base::Command::Option.remove_options_from_args(options, ['target1', '--stdout', 'target2'])
    assert_equal [{ stdout: true }, %w[target1 target2]],
                 RVGP::Base::Command::Option.remove_options_from_args(options, ['target1', 'target2', '--stdout'])

    options << RVGP::Base::Command::Option.new(:date, :d, { has_value: 'DATE' })

    assert_equal [{ stdout: true, date: '2022-01-01' }, %w[target1 target2]],
                 RVGP::Base::Command::Option.remove_options_from_args(
                   options, ['-d', '2022-01-01', 'target1', 'target2', '--stdout']
                 )

    assert_equal [{ stdout: true, date: '2022-01-01' }, %w[target1 target2]],
                 RVGP::Base::Command::Option.remove_options_from_args(
                   options, ['target1', '--date', '2022-01-01', 'target2', '--stdout']
                 )

    assert_equal [{ stdout: true, date: '2022-01-01' }, %w[target1 target2]],
                 RVGP::Base::Command::Option.remove_options_from_args(
                   options, ['target1', 'target2', '--date=2022-01-01', '--stdout']
                 )

    assert_equal [{ stdout: true, date: '2022-01-01' }, %w[target1 target2]],
                 RVGP::Base::Command::Option.remove_options_from_args(
                   options, ['target1', 'target2', '--stdout', '-d', '2022-01-01']
                 )

    assert_equal [{ stdout: true, date: '2022-01-01' }, %w[target1 target2]],
                 RVGP::Base::Command::Option.remove_options_from_args(
                   options, ['--stdout', '--date', '2022-01-01', 'target1', 'target2']
                 )

    # This is just kind of an odd one, make sure we don't try to parse the
    # --random=arg as an option:
    assert_equal [{ date: '2022-01-01' }, ['target1', 'target2', '--random=arg']],
                 RVGP::Base::Command::Option.remove_options_from_args(
                   options, ['--date', '2022-01-01', 'target1', 'target2', '--random=arg']
                 )

    # Note that date expects a value, yet, is at the end of the string:
    assert_raises RVGP::Base::Command::Option::UnexpectedEndOfArgs do
      RVGP::Base::Command::Option.remove_options_from_args(options, ['--stdout', 'target1', 'target2', '--date'])
    end
  end
end
