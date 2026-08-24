# frozen_string_literal: true

require 'json'
require 'open3'
require 'tmpdir'
require_relative '../../spec/spec_helper'
require_relative '../app/services/validate_task_files'
require_relative '../app/services/initialize_task'

RSpec.describe 'InitializeTask' do
  let(:service_class) { Object.const_get(:InitializeTask) }
  let(:db) { Database.connection }
  let(:root_path) { Dir.mktmpdir('initialize-task-spec') }
  let(:project_path) { File.join(root_path, 'project') }
  let(:task_path) { File.join(root_path, 'tasks', '0025-task') }

  around do |example|
    original_agent = ENV.fetch('AUTOIMPLEMENT_SUPER_REVIEW_AGENT', nil)
    ENV['AUTOIMPLEMENT_SUPER_REVIEW_AGENT'] = 'claude'
    example.run
  ensure
    ENV['AUTOIMPLEMENT_SUPER_REVIEW_AGENT'] = original_agent
  end

  before do
    initialize_git_project(project_path)
    write_authored_task(task_path)
    allow(ResolveProjectPath).to receive(:call).and_return(File.realpath(project_path))
  end

  after do
    FileUtils.remove_entry(root_path)
  end

  it 'creates one initialized Task using the environment super-review agent' do
    task = service_class.call(task_path: task_path)

    expect(task).to include(
      id: be_a(Integer),
      task_path: File.realpath(task_path),
      project_path: File.realpath(project_path),
      starting_commit_sha: git!('rev-parse', 'HEAD').strip,
      state: 'initialized',
      super_review_agent: 'claude'
    )
    expect(db[:tasks].count).to eq(1)
    expect(ResolveProjectPath).to have_received(:call)
  end

  it 'persists an explicit supported super-review agent before the environment value' do
    ENV['AUTOIMPLEMENT_SUPER_REVIEW_AGENT'] = 'claude'

    task = service_class.call(task_path: task_path, super_review_agent: 'none')

    expect(task.fetch(:super_review_agent)).to eq('none')
    expect(db[:tasks].where(id: task.fetch(:id)).get(:super_review_agent)).to eq('none')
  end

  it 'accepts none from the environment' do
    ENV['AUTOIMPLEMENT_SUPER_REVIEW_AGENT'] = 'none'

    task = service_class.call(task_path: task_path)

    expect(task.fetch(:super_review_agent)).to eq('none')
  end

  it 'requires a super-review policy for a new Task' do
    ENV.delete('AUTOIMPLEMENT_SUPER_REVIEW_AGENT')

    expect { service_class.call(task_path: task_path) }.
      to raise_error(
        'AUTOIMPLEMENT_SUPER_REVIEW_AGENT must be claude, codex, or none for a new Task'
      )
    expect(db[:tasks].count).to eq(0)
  end

  it 'resumes the same canonical Task without changing its super-review agent' do
    first_task = service_class.call(task_path: task_path, super_review_agent: 'codex')
    ENV['AUTOIMPLEMENT_SUPER_REVIEW_AGENT'] = 'none'
    second_task = service_class.call(task_path: task_path)
    matching_task = service_class.call(task_path: task_path, super_review_agent: 'codex')

    expect(second_task).to eq(first_task)
    expect(matching_task).to eq(first_task)
    expect(db[:tasks].count).to eq(1)
  end

  it 'rejects an unsupported explicit or environment super-review agent without mutation' do
    expect do
      service_class.call(task_path: task_path, super_review_agent: 'terra')
    end.to raise_error('Unsupported super-review agent terra; expected claude, codex, or none')
    expect(db[:tasks].count).to eq(0)

    ENV['AUTOIMPLEMENT_SUPER_REVIEW_AGENT'] = 'terra'
    expect { service_class.call(task_path: task_path) }.
      to raise_error('Unsupported super-review agent terra; expected claude, codex, or none')
    expect(db[:tasks].count).to eq(0)

    ENV['AUTOIMPLEMENT_SUPER_REVIEW_AGENT'] = 'none'
    task = service_class.call(task_path: task_path, super_review_agent: 'codex')

    expect do
      service_class.call(task_path: task_path, super_review_agent: 'claude')
    end.to raise_error(
      "Task #{task.fetch(:id)} super-review agent mismatch: expected codex, got claude"
    )
    expect(db[:tasks].where(id: task.fetch(:id)).get(:super_review_agent)).to eq('codex')
  end

  it 'uses the real Task path as its lifetime identity' do
    link_path = File.join(root_path, 'task-link')
    File.symlink(task_path, link_path)

    task = service_class.call(task_path: link_path)
    resumed_task = service_class.call(task_path: task_path)

    expect(task.fetch(:task_path)).to eq(File.realpath(task_path))
    expect(resumed_task.fetch(:id)).to eq(task.fetch(:id))
    expect(db[:tasks].count).to eq(1)
  end

  it 'rejects a different Task while one is active for the project' do
    active_task = service_class.call(task_path: task_path)
    other_task_path = File.join(root_path, 'tasks', '0026-other')
    write_authored_task(other_task_path)

    expect { service_class.call(task_path: other_task_path) }.
      to raise_error(
        "Task #{active_task.fetch(:id)} is already active for #{File.realpath(project_path)}: " \
        "#{File.realpath(task_path)}"
      )
    expect(db[:tasks].count).to eq(1)
  end

  it 'rejects creation while an Autofix Review is active for the project' do
    completed_task_id = db[:tasks].insert(
      created_at: Time.now,
      task_path: File.realpath(task_path),
      project_path: File.realpath(project_path),
      starting_commit_sha: git!('rev-parse', 'HEAD').strip,
      state: 'final_checks_passed',
      super_review_agent: 'claude'
    )
    review_id = db[:reviews].insert(
      created_at: Time.now,
      completed_at: nil,
      number: 1,
      source: 'local',
      starting_commit_sha: git!('rev-parse', 'HEAD').strip,
      state: 'manager_issues_assessment',
      task_id: completed_task_id
    )
    other_task_path = File.join(root_path, 'tasks', '0026-other')
    write_authored_task(other_task_path)

    expect { service_class.call(task_path: other_task_path) }.
      to raise_error("Review #{review_id} is already active for #{File.realpath(project_path)}")
    expect(db[:tasks].count).to eq(1)
  end

  it 'requires a clean working tree for creation' do
    File.write(File.join(project_path, 'tracked.txt'), "dirty\n")

    expect { service_class.call(task_path: task_path) }.
      to raise_error(/Working tree is not clean/)
    expect(db[:tasks].count).to eq(0)
  end

  it 'allows read-only resume from a dirty working tree' do
    task = service_class.call(task_path: task_path)
    stored_task = db[:tasks].where(id: task.fetch(:id)).first
    File.write(File.join(project_path, 'tracked.txt'), "dirty\n")

    expect(service_class.call(task_path: task_path)).to eq(stored_task)
    expect(db[:tasks].where(id: task.fetch(:id)).first).to eq(stored_task)
  end

  it 'rejects resume from another checkout' do
    task = service_class.call(task_path: task_path)
    other_project_path = File.join(root_path, 'other-project')
    initialize_git_project(other_project_path)
    allow(ResolveProjectPath).to receive(:call).and_return(File.realpath(other_project_path))

    expect { service_class.call(task_path: task_path) }.
      to raise_error(
        "Task #{task.fetch(:id)} checkout mismatch: expected #{File.realpath(project_path)}, " \
        "got #{File.realpath(other_project_path)}"
      )
  end

  it 'rejects resume from another branch' do
    task = service_class.call(task_path: task_path)
    git!('checkout', '-q', '-b', 'other')

    expect { service_class.call(task_path: task_path) }.
      to raise_error("Task #{task.fetch(:id)} branch mismatch: expected main, got other")
  end

  it 'uses updated Task config as the branch authority on resume' do
    task = service_class.call(task_path: task_path)
    write_task_config(task_path, branch_name: 'other')

    expect { service_class.call(task_path: task_path) }.
      to raise_error("Task #{task.fetch(:id)} branch mismatch: expected other, got main")
  end

  it 'requires complete Task branch config without database mutation' do
    File.write(File.join(task_path, 'config.json'), JSON.generate('branch' => { 'name' => 'main' }))

    expect { service_class.call(task_path: task_path) }.
      to raise_error('Missing Task branch config: original_base_ref')
    expect(db[:tasks].count).to eq(0)
  end

  it 'revalidates authored files on resume' do
    task = service_class.call(task_path: task_path)
    stored_task = db[:tasks].where(id: task.fetch(:id)).first
    File.write(File.join(task_path, 'steps.md'), "# Steps\n")

    expect { service_class.call(task_path: task_path) }.
      to raise_error(
        "No canonical Step heading in #{File.join(File.realpath(task_path), 'steps.md')}"
      )
    expect(db[:tasks].where(id: task.fetch(:id)).first).to eq(stored_task)
  end

  def initialize_git_project(path)
    FileUtils.mkdir_p(path)
    git!('init', '-q', '--initial-branch=main', path: path)
    git!('config', 'user.email', 'autoimplement@example.com', path: path)
    git!('config', 'user.name', 'Autoimplement', path: path)
    File.write(File.join(path, 'tracked.txt'), "initial\n")
    git!('add', 'tracked.txt', path: path)
    git!('commit', '-q', '-m', 'Initial commit', path: path)
  end

  def write_authored_task(path)
    FileUtils.mkdir_p(path)
    File.write(File.join(path, 'task.md'), "# Context\n")
    File.write(File.join(path, 'steps.md'), "# Steps\n\n## Step 1: Start\n")
    write_task_config(path)
  end

  def write_task_config(path, branch_name: 'main')
    File.write(
      File.join(path, 'config.json'),
      JSON.generate(
        'branch' => {
          'name' => branch_name,
          'original_base_ref' => 'base-sha',
          'original_base_commit_sha' => 'base-sha',
          'active_base_ref' => 'base-sha',
          'active_base_commit_sha' => 'base-sha'
        }
      )
    )
  end

  def git!(*arguments, path: project_path)
    stdout, stderr, status = Open3.capture3('git', '-C', path, *arguments)
    raise stderr unless status.success?

    stdout
  end
end
