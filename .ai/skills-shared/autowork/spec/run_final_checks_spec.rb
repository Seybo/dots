# frozen_string_literal: true

require 'yaml'
require_relative 'spec_helper'

RSpec.describe RunFinalChecks do
  let(:project_path) { Dir.mktmpdir('run-final-checks-spec') }
  let(:tool_path) { Dir.mktmpdir('run-final-checks-tools') }
  let(:command_log_path) { File.join(tool_path, 'commands.log') }
  let(:final_checks) { { '.' => [], 'components/package' => ['check-package'] } }
  let(:starting_commit_sha) { git!('rev-parse', 'HEAD').strip }

  around do |example|
    original_path = ENV.fetch('PATH')
    ENV['PATH'] = "#{tool_path}:#{original_path}"
    example.run
  ensure
    ENV['PATH'] = original_path
  end

  before do
    write_fake_check('check-root')
    write_fake_check('check-package')
    write_fake_check('check-first')
    write_fake_check('check-second')
    write_fake_check('check-failing')
    initialize_project
    starting_commit_sha
  end

  after do
    FileUtils.remove_entry(project_path)
    FileUtils.remove_entry(tool_path)
  end

  it 'runs only the longest matching component' do
    write_file('components/package/value.txt', "changed\n")
    commit_changes

    result = run_final_checks

    expect(result).to eq(
      output: "Final checks:\n- [components/package] check-package: passed (exit 0)",
      is_passing: true
    )
    expect(command_log).to eq(['check-package'])
  end

  context 'when a sibling path only shares the component name prefix' do
    let(:final_checks) { { '.' => ['check-root'], 'components/package' => ['check-package'] } }

    it 'selects the root component' do
      write_file('components/package-old/value.txt', "changed\n")
      commit_changes

      result = run_final_checks

      expect(result.fetch(:output)).to include('- [.] check-root: passed (exit 0)')
      expect(command_log).to eq(['check-root'])
    end
  end

  context 'when several components changed' do
    let(:final_checks) do
      {
        '.' => [],
        'components/second' => ['check-second'],
        'components/first' => ['check-first']
      }
    end

    it 'runs each component once in configuration order and renders an empty root component' do
      write_file('README.md', "changed\n")
      write_file('components/first/one.txt', "changed\n")
      write_file('components/first/two.txt', "changed\n")
      write_file('components/second/value.txt', "changed\n")
      commit_changes

      result = run_final_checks

      expect(result).to eq(
        output: "Final checks:\n" \
                "- [.]: skipped (no configured commands)\n" \
                "- [components/second] check-second: passed (exit 0)\n" \
                '- [components/first] check-first: passed (exit 0)',
        is_passing: true
      )
      expect(command_log).to eq(%w[check-second check-first])
    end
  end

  context 'when a file moves across components' do
    let(:final_checks) do
      {
        'components/package' => ['check-package'],
        'components/second' => ['check-second']
      }
    end

    it 'runs checks for both the old and new component' do
      git!('mv', 'components/package/tracked.txt', 'components/second/moved.txt')
      commit_changes

      result = run_final_checks

      expect(result.fetch(:output)).to include(
        '- [components/package] check-package: passed (exit 0)',
        '- [components/second] check-second: passed (exit 0)'
      )
      expect(command_log).to eq(%w[check-package check-second])
    end
  end

  context 'when one command fails' do
    let(:final_checks) do
      { 'components/package' => %w[check-failing check-package] }
    end

    it 'runs every command and renders every command output' do
      File.write(File.join(tool_path, 'fail-check-failing'), '')
      write_file('components/package/value.txt', "changed\n")
      commit_changes

      result = run_final_checks

      expect(result.fetch(:is_passing)).to be(false)
      expect(result.fetch(:output)).to include(
        '- [components/package] check-failing: failed (exit 3)',
        '- [components/package] check-package: passed (exit 0)',
        "[components/package] check-failing stdout:\ncheck-failing stdout",
        "[components/package] check-failing stderr:\ncheck-failing stderr",
        "[components/package] check-package stdout:\ncheck-package stdout",
        "[components/package] check-package stderr:\ncheck-package stderr"
      )
      expect(command_log).to eq(%w[check-failing check-package])
    end
  end

  it 'reports an unchanged Git range without running commands' do
    result = run_final_checks

    expect(result).to eq(
      output: "Final checks:\nSkipped: no changed files.",
      is_passing: true
    )
    expect(File).not_to exist(command_log_path)
  end

  it 'fails when the root configuration is missing' do
    FileUtils.rm(File.join(project_path, '.autowork.yml'))
    commit_changes

    expect { run_final_checks }.to raise_error(Errno::ENOENT)
    expect(File).not_to exist(command_log_path)
  end

  it 'fails when the root configuration is malformed' do
    File.write(File.join(project_path, '.autowork.yml'), "final_checks: [\n")
    commit_changes

    expect { run_final_checks }.to raise_error(Psych::SyntaxError)
    expect(File).not_to exist(command_log_path)
  end

  it 'fails when the configuration omits final_checks' do
    File.write(File.join(project_path, '.autowork.yml'), YAML.dump('other' => {}))
    commit_changes

    expect { run_final_checks }.to raise_error(KeyError, /final_checks/)
    expect(File).not_to exist(command_log_path)
  end

  it 'fails when a selected component directory does not exist' do
    FileUtils.rm_rf(File.join(project_path, 'components/package'))
    commit_changes

    expect { run_final_checks }.
      to raise_error(RuntimeError, %r{Final-check directory does not exist: .*components/package})
    expect(File).not_to exist(command_log_path)
  end

  it 'surfaces Git failures before running commands' do
    expect { run_final_checks(commit_sha: 'missing-commit') }.
      to raise_error(RuntimeError, /git diff .* failed with exit/)
    expect(File).not_to exist(command_log_path)
  end

  it 'propagates an interrupted check without producing a result' do
    write_file('components/package/value.txt', "changed\n")
    commit_changes
    command = ['bash', '-c', 'check-package', { chdir: File.join(project_path, 'components/package') }]
    allow(Open3).to receive(:capture3).and_call_original
    allow(Open3).to receive(:capture3).with(*command).and_raise(Interrupt)

    expect { run_final_checks }.to raise_error(Interrupt)
    expect(File).not_to exist(command_log_path)
  end

  it 'propagates a process execution error without producing a result' do
    write_file('components/package/value.txt', "changed\n")
    commit_changes
    command = ['bash', '-c', 'check-package', { chdir: File.join(project_path, 'components/package') }]
    allow(Open3).to receive(:capture3).and_call_original
    allow(Open3).to receive(:capture3).with(*command).and_raise(Errno::ENOENT)

    expect { run_final_checks }.to raise_error(Errno::ENOENT)
    expect(File).not_to exist(command_log_path)
  end

  private

  def initialize_project
    git!('init', '-q')
    git!('config', 'user.email', 'checks@example.com')
    git!('config', 'user.name', 'Checks')
    final_checks.each_key do |directory|
      next if directory == '.'

      write_file(File.join(directory, 'tracked.txt'), "initial\n")
    end
    write_config
    git!('add', '.')
    git!('commit', '-q', '-m', 'Initial commit')
  end

  def write_config
    File.write(
      File.join(project_path, '.autowork.yml'),
      YAML.dump('final_checks' => final_checks)
    )
  end

  def write_file(relative_path, content)
    path = File.join(project_path, relative_path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end

  def commit_changes
    git!('add', '-A')
    git!('commit', '-q', '-m', 'Change files')
  end

  def run_final_checks(commit_sha: starting_commit_sha)
    described_class.call(
      project_path: project_path,
      starting_commit_sha: commit_sha
    )
  end

  def git!(*arguments)
    stdout, stderr, status = Open3.capture3('git', '-C', project_path, *arguments)
    raise stderr unless status.success?

    stdout
  end

  def write_fake_check(name)
    File.write(
      File.join(tool_path, name),
      <<~SH
        #!/bin/sh
        name="$(basename "$0")"
        printf '%s\n' "$name" >> "#{command_log_path}"
        printf '%s stdout\n' "$name"
        printf '%s stderr\n' "$name" >&2
        if [ -f "#{File.join(tool_path, "fail-#{name}")}" ]; then
          exit 3
        fi
      SH
    )
    File.chmod(0o755, File.join(tool_path, name))
  end

  def command_log
    File.readlines(command_log_path, chomp: true)
  end
end
