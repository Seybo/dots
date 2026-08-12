#!/usr/bin/env ruby
# frozen_string_literal: true

require 'open3'
require 'shellwords'

module Hunkit
  class Error < StandardError; end

  CommandResult = Struct.new(:stdout, :stderr, :exit_status)
  Pane = Struct.new(:id, :left, :top, :width, :height, :command, :is_dead, keyword_init: true)

  class Runner
    WINDOW_FORMAT = "\#{window_id}"
    PANE_FORMAT = "\#{pane_id}|\#{pane_left}|\#{pane_top}|\#{pane_width}|\#{pane_height}|" \
                  "\#{pane_current_command}|\#{pane_dead}"

    def initialize(env: ENV, cwd: Dir.pwd, output: $stdout, command_runner: nil)
      @env = env
      @cwd = File.expand_path(cwd)
      @output = output
      @command_runner = command_runner || method(:capture)
    end

    def run
      current_pane = validate_tmux_context!
      repository = resolve_repository
      validate_hunk!
      validate_working_tree_diff!(repository)
      target_pane = resolve_right_pane(current_pane)
      validate_idle_shell!(target_pane)
      launch_hunk(repository, target_pane.id)

      @output.puts 'Hunk launched.'
      @output.puts "Repository: #{repository}"
      @output.puts "Pane: #{target_pane.id}"
      repository
    end

    private

    def capture(command)
      stdout, stderr, status = Open3.capture3(*command)
      CommandResult.new(stdout, stderr, status.exitstatus)
    rescue Errno::ENOENT => err
      CommandResult.new('', err.message, 127)
    end

    def command(*arguments)
      @command_runner.call(arguments)
    end

    def validate_tmux_context!
      current_pane = @env['TMUX_PANE'].to_s
      if @env['TMUX'].to_s.empty? || current_pane.empty?
        raise Error, 'Hunkit requires the current Pi to run inside a tmux session'
      end

      current_pane
    end

    def resolve_repository
      result = command('git', '-C', @cwd, 'rev-parse', '--show-toplevel')
      raise Error, 'Current directory is not inside a Git repository' unless result.exit_status.zero?

      path = result.stdout.strip
      raise Error, 'Git repository root is empty' if path.empty?

      File.realpath(path)
    rescue Errno::ENOENT
      raise Error, 'Git repository root does not exist'
    end

    def validate_hunk!
      result = command('hunk', '--version')
      raise Error, 'Hunk is unavailable on PATH' unless result.exit_status.zero?
    end

    def validate_working_tree_diff!(repository)
      diff = command('git', '-C', repository, 'diff', '--quiet', '--exit-code', '--')
      return if diff.exit_status == 1
      raise Error, 'Unable to inspect the working-tree diff' unless diff.exit_status.zero?

      untracked = command('git', '-C', repository, 'ls-files', '--others', '--exclude-standard')
      raise Error, 'Unable to inspect untracked files' unless untracked.exit_status.zero?
      raise Error, 'No working-tree diff for Hunk to display' if untracked.stdout.strip.empty?
    end

    def resolve_right_pane(current_pane_id)
      panes = panes_in_current_window(current_pane_id)
      current = find_current_pane(panes, current_pane_id)
      candidates = directly_adjacent_right_panes(panes, current)

      raise Error, 'No directly adjacent right pane is available' if candidates.empty?
      raise Error, 'Hunkit requires exactly one directly adjacent right pane' unless candidates.one?

      candidates.first
    end

    def panes_in_current_window(current_pane_id)
      window = command('tmux', 'display-message', '-p', '-t', current_pane_id, WINDOW_FORMAT)
      raise Error, 'Unable to resolve the current tmux window' unless window.exit_status.zero?

      result = command('tmux', 'list-panes', '-t', window.stdout.strip, '-F', PANE_FORMAT)
      raise Error, 'Unable to inspect panes in the current tmux window' unless result.exit_status.zero?

      result.stdout.lines.filter_map { |line| parse_pane(line) }
    end

    def find_current_pane(panes, current_pane_id)
      panes.find { |pane| pane.id == current_pane_id } ||
        raise(Error, 'Current Pi pane is missing from its tmux window')
    end

    def directly_adjacent_right_panes(panes, current)
      right_edge = current.left + current.width + 1
      panes.reject { |pane| pane.id == current.id }.select do |pane|
        pane.left == right_edge && vertically_overlaps?(current, pane)
      end
    end

    def parse_pane(line)
      id, left, top, width, height, pane_command, dead = line.strip.split('|', 7)
      return if [id, left, top, width, height, pane_command, dead].any?(&:nil?)

      Pane.new(
        id: id,
        left: Integer(left, 10),
        top: Integer(top, 10),
        width: Integer(width, 10),
        height: Integer(height, 10),
        command: pane_command,
        is_dead: dead == '1'
      )
    rescue ArgumentError
      nil
    end

    def vertically_overlaps?(first, second)
      first_bottom = first.top + first.height - 1
      second_bottom = second.top + second.height - 1
      first.top <= second_bottom && second.top <= first_bottom
    end

    def validate_idle_shell!(pane)
      shell = File.basename(@env['SHELL'].to_s)
      raise Error, 'SHELL is unavailable' if shell.empty?

      return if !pane.is_dead && pane.command == shell

      raise Error, "Right pane #{pane.id} must be an idle #{shell} shell"
    end

    def launch_hunk(repository, target_pane)
      pane_command = "(cd #{repository.shellescape} && hunk diff --watch)"
      result = command('tmux', 'send-keys', '-t', target_pane, pane_command, 'C-m')
      return if result.exit_status.zero?

      detail = result.stderr.strip
      message = "Failed to launch Hunk in pane #{target_pane}"
      message = "#{message}: #{detail}" unless detail.empty?
      raise Error, message
    end
  end

  def self.cli(argv, env: ENV, output: $stdout, error: $stderr)
    raise Error, 'Usage: hunkit.rb' unless argv.empty?

    Runner.new(env: env, output: output).run
    0
  rescue Error => err
    error.puts err.message
    2
  end
end

exit Hunkit.cli(ARGV) if $PROGRAM_NAME == __FILE__
