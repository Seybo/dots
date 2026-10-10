# frozen_string_literal: true

require 'minitest/autorun'
require 'stringio'

require_relative '../scripts/hunkit'

# Exercises command-line routing without entering the launch workflow.
class HunkitCliSpec < Minitest::Test
  def test_without_arguments_prints_help_without_launching
    output = StringIO.new
    error = StringIO.new

    status = Hunkit.cli([], env: {}, output: output, error: error)

    assert_equal 0, status
    assert_includes output.string, 'hunkit.rb --diff'
    assert_includes output.string, 'hunkit.rb <commit>'
    assert_empty error.string
  end

  def test_rejects_multiple_arguments
    output = StringIO.new
    error = StringIO.new

    status = Hunkit.cli(%w[--diff HEAD], env: {}, output: output, error: error)

    assert_equal 2, status
    assert_empty output.string
    assert_includes error.string, 'Usage:'
  end

  def test_rejects_unknown_options
    output = StringIO.new
    error = StringIO.new

    status = Hunkit.cli(['--staged'], env: {}, output: output, error: error)

    assert_equal 2, status
    assert_empty output.string
    assert_includes error.string, 'Usage:'
  end
end
