# frozen_string_literal: true

require 'json'
require 'tmpdir'
require_relative 'spec_helper'

RSpec.describe 'Task config services' do
  let(:reader_class) { Object.const_get(:ReadTaskConfig) }
  let(:updater_class) { Object.const_get(:UpdateTaskConfig) }
  let(:root_path) { Dir.mktmpdir('task-config-spec') }
  let(:task_path) { File.join(root_path, 'task') }
  let(:config) do
    {
      'branch' => {
        'name' => 'feature',
        'original_base_ref' => 'origin/main',
        'original_base_commit_sha' => 'original-sha',
        'active_base_ref' => 'origin/main',
        'active_base_commit_sha' => 'active-sha'
      },
      'future' => { 'setting' => true }
    }
  end

  before do
    FileUtils.mkdir_p(task_path)
    write_config(config)
  end

  after do
    FileUtils.remove_entry(root_path)
  end

  it 'reads validated complete Task configuration' do
    expect(read_config).to eq(config)
  end

  it 'updates only active base fields and preserves unrelated configuration' do
    result = updater_class.call(
      task_path: task_path,
      active_base_ref: 'origin/release',
      active_base_commit_sha: 'release-sha'
    )

    expected = config.merge(
      'branch' => config.fetch('branch').merge(
        'active_base_ref' => 'origin/release',
        'active_base_commit_sha' => 'release-sha'
      )
    )
    expect(result).to eq(expected)
    expect(JSON.parse(File.read(config_path))).to eq(expected)
    expect(Dir.glob("#{config_path}.tmp*")).to be_empty
  end

  it 'rejects missing, malformed, or incomplete configuration' do
    FileUtils.rm_f(config_path)
    expect { read_config }.
      to raise_error("Missing Task config: #{File.join(File.realpath(task_path), 'config.json')}")

    File.write(config_path, '{')
    expect { read_config }.to raise_error(JSON::ParserError)

    write_config('branch' => { 'name' => 'feature' })
    expect { read_config }.to raise_error('Missing Task branch config: original_base_ref')
  end

  it 'rejects blank existing and replacement values' do
    invalid_config = config
    invalid_config.fetch('branch')['name'] = '  '
    write_config(invalid_config)

    expect { read_config }.
      to raise_error('Task branch config name must be a non-empty string')

    write_config(config.merge('branch' => config.fetch('branch').merge('name' => 'feature')))
    expect do
      updater_class.call(
        task_path: task_path,
        active_base_ref: '',
        active_base_commit_sha: 'sha'
      )
    end.to raise_error('Active base ref must be a non-empty string')
  end

  private

  def read_config
    reader_class.call(task_path: task_path)
  end

  def config_path
    File.join(task_path, 'config.json')
  end

  def write_config(value)
    File.write(config_path, "#{JSON.pretty_generate(value)}\n")
  end
end
