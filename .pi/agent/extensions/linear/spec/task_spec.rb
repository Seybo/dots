# frozen_string_literal: true

require 'rspec'
require 'tmpdir'
require 'fileutils'
require_relative '../lib/task'

RSpec.describe Linear::Task do
  let(:client) { instance_double(Linear::Client) }
  let(:issue) do
    { 'id' => 'issue-uuid', 'identifier' => 'HC-123', 'title' => 'Fix checkout', 'description' => '# Body',
      'url' => 'https://linear.app/shakacode/issue/HC-123/fix', 'branchName' => 'provider/hc-123-fix',
      'team' => { 'id' => 'team', 'key' => 'HC' } }
  end
  let(:destination) { { 'team_id' => 'team' } }
  let(:task) { described_class.new(client: client, registry: @registry) }
  let(:source) { File.join(@task_root, 'draft01', 'task.md') }

  before do
    scratch = File.expand_path('../../../../../agents_tmp', __dir__)
    FileUtils.mkdir_p(scratch)
    @root = Dir.mktmpdir('linear-spec-', scratch)
    @task_root = File.join(@root, '_tasks')
    FileUtils.mkdir_p(File.dirname(source))
    File.write(source, "# Story details\n\nName: Fix checkout\n\n# Context\n\nBody\n")
    registry_path = File.join(@root, 'projects.yml')
    File.write(registry_path, { 'projects' => {
      'hc' => { 'checkout_layout' => 'direct', 'checkout_path' => @root, 'task_provider' => 'linear',
                'linear' => { 'workspace' => 'shakacode', 'team' => 'HC', 'status' => 'Ready for Development' } },
      'local' => { 'checkout_layout' => 'direct', 'checkout_path' => @root, 'task_provider' => 'local' }
    } }.to_yaml)
    @registry = Linear::Registry.new(path: registry_path)
    allow(client).to receive(:discover).and_return(destination)
    allow(client).to receive(:create_issue).and_return(issue)
    allow(client).to receive(:get_issue).and_return(issue)
    allow(client).to receive(:identifier).and_return('HC-123')
  end

  after { FileUtils.remove_entry(@root) }

  it 'converts a draft and returns handoff context without changing authored content' do
    original = File.read(source)
    result = task.convert('hc', source, 'Bug')
    path = File.join(@task_root, 'HC-123-fix-checkout', 'task.md')
    expect(result).to include('task_path' => path, 'branchName' => 'provider/hc-123-fix')
    expect(File.read(path)).to eq(original)
    expect(File.exist?(source)).to be(false)
    expect(File.exist?(File.join(@root, '.git'))).to be(false)
    expect(client).to have_received(:create_issue).with(
      { 'title' => 'Fix checkout', 'description' => "# Context\n\nBody\n", 'type' => 'Bug' }, destination
    )
    expect(JSON.parse(File.read(File.join(File.dirname(path), 'config.json'))).fetch('linear'))
      .to include('id' => 'issue-uuid', 'identifier' => 'HC-123', 'branch_name' => 'provider/hc-123-fix')
    expect(JSON.parse(File.read(File.join(File.dirname(path), 'config.json'))).keys).to eq(['linear'])
  end

  it 'preserves unrelated task metadata' do
    File.write(File.join(File.dirname(source), 'config.json'), JSON.generate('other' => { 'value' => 1 }))
    result = task.convert('hc', source, 'Chore')
    config = JSON.parse(File.read(File.join(File.dirname(result.fetch('task_path')), 'config.json')))
    expect(config.fetch('other')).to eq('value' => 1)
  end

  it 'imports an existing issue without a mutation and exposes the title for later updates' do
    result = task.import('hc', 'HC-123')
    expect(File.read(result.fetch('task_path'))).to include('Name: Fix checkout', '# Body')
    expect(client).not_to have_received(:create_issue)
    expect(result).to include('identifier' => 'HC-123', 'url' => issue.fetch('url'))
  end

  ['Plain-text description', "## Details\n\nBody", "Preamble\n\n# Details\n\nBody"].each do |description|
    it "preserves imported content on explicit update: #{description.lines.first.strip}" do
      issue['description'] = description
      result = task.import('hc', 'HC-123')
      allow(client).to receive(:update_issue).and_return(issue)

      task.update('HC-123', result.fetch('task_path'))

      expect(client).to have_received(:update_issue).with(
        'issue-uuid', 'title' => 'Fix checkout', 'description' => "# Context\n\n#{description}"
      )
    end
  end

  it 'leaves the draft untouched after failed or uncertain creation' do
    original = File.read(source)
    allow(client).to receive(:create_issue).and_raise(Linear::Error, 'Uncertain; inspect Linear')
    expect { task.convert('hc', source, 'Bug') }.to raise_error(Linear::Error, /inspect Linear/)
    expect(File.read(source)).to eq(original)
    expect(File.exist?(File.join(File.dirname(source), 'config.json'))).to be(false)
  end

  it 'records a successful remote creation even when a local destination collision prevents rename' do
    FileUtils.mkdir_p(File.join(@task_root, 'HC-123-fix-checkout'))
    expect { task.convert('hc', source, 'Bug') }.to raise_error(Linear::Error, /HC-123/)
    expect(File.exist?(source)).to be(true)
    expect { task.convert('hc', source, 'Bug') }.to raise_error(Linear::Error, /already associated/)
    expect(client).to have_received(:create_issue).once
  end

  it 'rejects an existing issue task before creating another remote issue' do
    FileUtils.mkdir_p(File.join(@task_root, 'HC-123-other-title'))
    expect { task.import('hc', 'HC-123') }.to raise_error(Linear::Error, /already exists/)
    expect(client).not_to have_received(:create_issue)
  end

  it 'rejects paths outside the project, nesting, unsupported providers and missing titles before creation' do
    expect { task.convert('hc', File.join(@root, 'task.md'), 'Bug') }.to raise_error(Linear::Error)
    expect { task.convert('local', source, 'Bug') }.to raise_error(Linear::Error, /task_provider/)
    nested = File.join(File.dirname(source), 'nested', 'task.md')
    FileUtils.mkdir_p(File.dirname(nested))
    File.write(nested, File.read(source))
    expect { task.convert('hc', nested, 'Bug') }.to raise_error(Linear::Error, /direct child/)
    File.write(source, '# Context')
    expect { task.convert('hc', source, 'Bug') }.to raise_error(Linear::Error, /Name:/)
    expect(client).not_to have_received(:create_issue)
  end

  it 'rejects an imported issue from a different team' do
    issue['team']['id'] = 'another-team'
    expect { task.import('hc', 'HC-123') }.to raise_error(Linear::Error, /team/)
  end

  it 'finds updates by the full identifier and rejects ambiguous folders' do
    result = task.convert('hc', source, 'Bug')
    expect(@registry.task_path('HC-123')).to eq(result.fetch('task_path'))
    allow(client).to receive(:update_issue).and_return(issue)
    task.update('HC-123')
    expect(client).to have_received(:update_issue).with('issue-uuid', hash_including('title' => 'Fix checkout'))
    second = File.join(@task_root, 'HC-123-other', 'task.md')
    FileUtils.mkdir_p(File.dirname(second))
    File.write(second, 'Other')
    expect { task.update('HC-123') }.to raise_error(Linear::Error, /exactly one/)
  end

  it 'uses recorded UUID identity for explicit updates and rejects mismatches' do
    result = task.convert('hc', source, 'Feature')
    allow(client).to receive(:update_issue).and_return(issue)
    task.update('HC-123', result.fetch('task_path'))
    expect(client).to have_received(:update_issue).with('issue-uuid', hash_including('title' => 'Fix checkout'))
    issue['id'] = 'different-uuid'
    expect { task.update('HC-123', result.fetch('task_path')) }.to raise_error(Linear::Error, /identity/)
  end
end
