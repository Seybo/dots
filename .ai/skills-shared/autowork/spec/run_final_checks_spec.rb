# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe RunFinalChecks do
  let(:project_path) { Dir.mktmpdir('run-final-checks-spec') }
  let(:tool_path) { Dir.mktmpdir('run-final-checks-tools') }
  let(:command_log_path) { File.join(tool_path, 'commands.log') }
  let(:original_path) { ENV.fetch('PATH') }

  before do
    ENV['PATH'] = "#{tool_path}:#{original_path}"
    write_fake_bundle
  end

  after do
    ENV['PATH'] = original_path
    FileUtils.remove_entry(project_path)
    FileUtils.remove_entry(tool_path)
  end

  it 'passes with the existing skip output when the project has no root Gemfile' do
    result = described_class.call(project_path: project_path)

    expect(result).to eq(
      output: "Final checks:\nSkipped: no Gemfile.",
      is_passing: true
    )
    expect(File).not_to exist(command_log_path)
  end

  it 'runs both Ruby checks in order and keeps successful output concise' do
    write_gemfile

    result = described_class.call(project_path: project_path)

    expect(result).to eq(
      output: "Final checks:\n" \
              "- bundle exec rubocop: passed (exit 0)\n" \
              '- bundle exec rspec: passed (exit 0)',
      is_passing: true
    )
    expect(File.readlines(command_log_path, chomp: true)).to eq(%w[rubocop rspec])
    expect(result.fetch(:output)).not_to include('stdout', 'stderr')
  end

  it 'runs every check after a failure and renders output from both commands' do
    write_gemfile
    File.write(File.join(tool_path, 'fail-rubocop'), '')

    result = described_class.call(project_path: project_path)

    expect(result.fetch(:is_passing)).to be(false)
    expect(result.fetch(:output)).to include(
      '- bundle exec rubocop: failed (exit 3)',
      '- bundle exec rspec: passed (exit 0)',
      "bundle exec rubocop stdout:\nrubocop stdout",
      "bundle exec rubocop stderr:\nrubocop stderr",
      "bundle exec rspec stdout:\nrspec stdout",
      "bundle exec rspec stderr:\nrspec stderr"
    )
    expect(File.readlines(command_log_path, chomp: true)).to eq(%w[rubocop rspec])
  end

  it 'propagates an interrupted check without producing a result' do
    write_gemfile
    command = ['bash', '-c', 'bundle exec rubocop', { chdir: project_path }]
    allow(Open3).to receive(:capture3).with(*command).and_raise(Interrupt)

    expect { described_class.call(project_path: project_path) }.to raise_error(Interrupt)
    expect(File).not_to exist(command_log_path)
  end

  it 'propagates a process execution error without producing a result' do
    write_gemfile
    command = ['bash', '-c', 'bundle exec rubocop', { chdir: project_path }]
    allow(Open3).to receive(:capture3).with(*command).and_raise(Errno::ENOENT)

    expect { described_class.call(project_path: project_path) }.to raise_error(Errno::ENOENT)
    expect(File).not_to exist(command_log_path)
  end

  private

  def write_gemfile
    File.write(File.join(project_path, 'Gemfile'), "source 'https://rubygems.org'\n")
  end

  def write_fake_bundle
    File.write(
      File.join(tool_path, 'bundle'),
      <<~SH
        #!/bin/sh
        printf '%s\\n' "$2" >> "#{command_log_path}"
        printf '%s stdout\\n' "$2"
        printf '%s stderr\\n' "$2" >&2
        if [ "$2" = rubocop ] && [ -f "#{File.join(tool_path, 'fail-rubocop')}" ]; then
          exit 3
        fi
      SH
    )
    File.chmod(0o755, File.join(tool_path, 'bundle'))
  end
end
