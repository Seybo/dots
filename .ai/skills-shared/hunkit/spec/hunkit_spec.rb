# frozen_string_literal: true

require 'fileutils'
require 'minitest/autorun'
require 'stringio'
require 'tmpdir'

require_relative '../scripts/hunkit'

class HunkitSpec < Minitest::Test
  def setup
    @root = File.realpath(Dir.mktmpdir('hunkit-'))
    @repo = File.join(@root, 'repo')
    @cwd = File.join(@repo, 'nested')
    FileUtils.mkdir_p(@cwd)
    @env = { 'TMUX' => 'tmux', 'TMUX_PANE' => '%1', 'SHELL' => '/bin/zsh' }
    @responses = {}
    @calls = []
    add_default_responses
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  def test_launches_hunk_in_the_only_directly_adjacent_idle_right_pane
    output = StringIO.new

    repository = runner(output: output).run

    assert_equal @repo, repository
    assert_includes output.string, "Repository: #{@repo}"
    assert_includes output.string, 'Pane: %2'
    assert_includes @calls, [
      'tmux', 'send-keys', '-t', '%2',
      "(cd #{@repo} && hunk diff --watch)", 'C-m'
    ]
  end

  def test_rejects_a_missing_tmux_context_without_sending_keys
    @env.delete('TMUX')

    error = assert_raises(Hunkit::Error) { runner.run }

    assert_match(/tmux session/, error.message)
    assert_no_keys_sent
  end

  def test_rejects_a_directory_outside_a_git_repository_without_sending_keys
    respond(['git', '-C', @cwd, 'rev-parse', '--show-toplevel'], status: 128, stderr: 'not a git repository')

    error = assert_raises(Hunkit::Error) { runner.run }

    assert_match(/Git repository/, error.message)
    assert_no_keys_sent
  end

  def test_rejects_when_hunk_is_unavailable_without_sending_keys
    respond(['hunk', '--version'], status: 127, stderr: 'command not found')

    error = assert_raises(Hunkit::Error) { runner.run }

    assert_match(/Hunk is unavailable/, error.message)
    assert_no_keys_sent
  end

  def test_launches_for_an_untracked_only_diff
    respond(['git', '-C', @repo, 'diff', '--quiet', '--exit-code', '--'], status: 0)
    respond(
      ['git', '-C', @repo, 'ls-files', '--others', '--exclude-standard'],
      stdout: "new-file.rb\n"
    )

    assert_equal @repo, runner.run
    assert(@calls.any? { |command| command.first(2) == %w[tmux send-keys] })
  end

  def test_rejects_an_empty_or_staged_only_diff_without_sending_keys
    respond(['git', '-C', @repo, 'diff', '--quiet', '--exit-code', '--'], status: 0)
    respond(['git', '-C', @repo, 'ls-files', '--others', '--exclude-standard'], stdout: '')

    error = assert_raises(Hunkit::Error) { runner.run }

    assert_match(/No working-tree diff/, error.message)
    assert_no_keys_sent
  end

  def test_rejects_when_there_is_no_directly_adjacent_right_pane
    pane_rows = "%1|0|0|160|40|pi|0\n%2|0|41|160|20|zsh|0\n"
    respond(list_panes_command, stdout: pane_rows)

    error = assert_raises(Hunkit::Error) { runner.run }

    assert_match(/directly adjacent right pane/, error.message)
    assert_no_keys_sent
  end

  def test_rejects_an_ambiguous_split_on_the_right
    pane_rows = <<~ROWS
      %1|0|0|80|40|pi|0
      %2|81|0|79|20|zsh|0
      %3|81|21|79|19|zsh|0
    ROWS
    respond(list_panes_command, stdout: pane_rows)

    error = assert_raises(Hunkit::Error) { runner.run }

    assert_match(/exactly one directly adjacent right pane/, error.message)
    assert_no_keys_sent
  end

  def test_rejects_a_busy_right_pane_without_sending_keys
    pane_rows = "%1|0|0|80|40|pi|0\n%2|81|0|79|40|ruby|0\n"
    respond(list_panes_command, stdout: pane_rows)

    error = assert_raises(Hunkit::Error) { runner.run }

    assert_match(/idle zsh shell/, error.message)
    assert_no_keys_sent
  end

  def test_rejects_a_dead_right_pane_without_sending_keys
    pane_rows = "%1|0|0|80|40|pi|0\n%2|81|0|79|40|zsh|1\n"
    respond(list_panes_command, stdout: pane_rows)

    error = assert_raises(Hunkit::Error) { runner.run }

    assert_match(/idle zsh shell/, error.message)
    assert_no_keys_sent
  end

  private

  def add_default_responses
    respond(['git', '-C', @cwd, 'rev-parse', '--show-toplevel'], stdout: "#{@repo}\n")
    respond(['hunk', '--version'], stdout: "hunk 0.17.7\n")
    respond(['git', '-C', @repo, 'diff', '--quiet', '--exit-code', '--'], status: 1)
    respond(['tmux', 'display-message', '-p', '-t', '%1', Hunkit::Runner::WINDOW_FORMAT], stdout: "@4\n")
    respond(
      list_panes_command,
      stdout: "%1|0|0|80|40|pi|0\n%2|81|0|79|40|zsh|0\n"
    )
    respond(
      ['tmux', 'send-keys', '-t', '%2', "(cd #{@repo} && hunk diff --watch)", 'C-m']
    )
  end

  def list_panes_command
    ['tmux', 'list-panes', '-t', '@4', '-F', Hunkit::Runner::PANE_FORMAT]
  end

  def respond(command, stdout: '', stderr: '', status: 0)
    @responses[command] = Hunkit::CommandResult.new(stdout, stderr, status)
  end

  def runner(output: StringIO.new)
    Hunkit::Runner.new(
      env: @env,
      cwd: @cwd,
      output: output,
      command_runner: lambda do |command|
        @calls << command
        @responses.fetch(command) do
          raise "Unexpected command: #{command.inspect}"
        end
      end
    )
  end

  def assert_no_keys_sent
    refute(@calls.any? { |command| command.first(2) == %w[tmux send-keys] })
  end
end
