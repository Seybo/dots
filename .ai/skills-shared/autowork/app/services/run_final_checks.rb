# frozen_string_literal: true

require 'open3'
require 'yaml'

class RunFinalChecks
  include ServiceObject

  PASSING_CHECK_STATUSES = %w[passed skipped].freeze

  arguments :project_path, :starting_commit_sha

  def call
    results = final_check_results
    {
      output: render_results(results),
      is_passing: results.all? { |result| PASSING_CHECK_STATUSES.include?(result.fetch(:status)) }
    }
  end

  private

  def final_check_results
    checks = configured_checks
    paths = changed_paths
    return [{ status: 'skipped', reason: 'no_changed_files' }] if paths.empty?

    selected_components(checks, paths).flat_map do |component, commands|
      run_component(component, commands)
    end
  end

  def configured_checks
    YAML.safe_load_file(File.join(project_path, '.autowork.yml')).fetch('final_checks')
  end

  def changed_paths
    range = "#{starting_commit_sha}..HEAD"
    stdout, stderr, status = Open3.capture3(
      'git', '-C', project_path, 'diff', '--name-only', '--no-renames', range
    )
    raise "git diff #{range} failed with exit #{status.exitstatus}: #{stderr.strip}" unless status.success?

    stdout.lines(chomp: true).reject(&:empty?)
  end

  def selected_components(checks, paths)
    selected = paths.map { |path| matching_component(checks.keys, path) }.uniq
    checks.each_with_object({}) do |(component, commands), chosen|
      chosen[component] = commands if selected.include?(component)
    end
  end

  def matching_component(components, path)
    components.
      select { |component| component == '.' || path == component || path.start_with?("#{component}/") }.
      max_by { |component| component == '.' ? 0 : component.length } ||
      raise("No final-check component configured for #{path}")
  end

  def run_component(component, commands)
    directory = File.expand_path(component, project_path)
    raise "Final-check directory does not exist: #{directory}" unless Dir.exist?(directory)

    return [{ component: component, status: 'skipped' }] if commands.empty?

    commands.map { |command| run_command(component, directory, command) }
  end

  def run_command(component, directory, command)
    stdout, stderr, status = Open3.capture3('bash', '-c', command, chdir: directory)
    {
      component: component,
      command: command,
      status: status.success? ? 'passed' : 'failed',
      exit_status: status.exitstatus,
      stdout: stdout,
      stderr: stderr
    }
  end

  def render_results(results)
    return "Final checks:\nSkipped: no changed files." if no_changed_files?(results)

    lines = ['Final checks:', *results.map { |result| result_line(result) }]
    lines.concat(command_output_lines(results)) if results.any? { |result| result.fetch(:status) == 'failed' }
    lines.join("\n")
  end

  def no_changed_files?(results)
    results.one? && results.first[:reason] == 'no_changed_files'
  end

  def result_line(result)
    return "- [#{result.fetch(:component)}]: skipped (no configured commands)" if result.fetch(:status) == 'skipped'

    "- #{result_label(result)}: #{result.fetch(:status)} (exit #{result.fetch(:exit_status)})"
  end

  def command_output_lines(results)
    results.reject { |result| result.fetch(:status) == 'skipped' }.flat_map do |result|
      [
        "#{result_label(result)} stdout:\n#{result.fetch(:stdout)}",
        "#{result_label(result)} stderr:\n#{result.fetch(:stderr)}",
      ]
    end
  end

  def result_label(result)
    "[#{result.fetch(:component)}] #{result.fetch(:command)}"
  end
end
