# frozen_string_literal: true

require 'json'
require 'open3'
require 'tmpdir'
require_relative '../../spec/spec_helper'

RSpec.describe 'LoadCompletedTask' do
  let(:service_class) { Object.const_get(:LoadCompletedTask) }
  let(:root_path) { Dir.mktmpdir('load-completed-task-spec') }
  let(:project_path) { File.join(root_path, 'project') }
  let(:task_path) { File.join(root_path, 'tasks', '0036-task') }
  let(:task_id) { insert_task }

  before do
    initialize_git_project
    write_task_files
  end

  after do
    FileUtils.remove_entry(root_path)
  end

  it 'loads one completed Task and validated config for the current checkout' do
    task_id

    result = service_class.call(task_path: task_path, project_path: project_path)

    expect(result.fetch(:task)).to include(
      id: task_id,
      task_path: File.realpath(task_path),
      project_path: File.realpath(project_path),
      state: 'final_checks_passed'
    )
    expect(result.fetch(:config).fetch('branch')).to include(
      'name' => 'feature',
      'active_base_ref' => 'main',
      'active_base_commit_sha' => head_sha
    )
  end

  it 'requires a persisted completed Task' do
    expect do
      service_class.call(task_path: task_path, project_path: project_path)
    end.to raise_error("No Autoimplement Task for #{File.realpath(task_path)}")

    task_id
    db[:tasks].where(id: task_id).update(state: 'initialized')

    expect do
      service_class.call(task_path: task_path, project_path: project_path)
    end.to raise_error("Task #{task_id} is not completed")
  end

  it 'requires the persisted checkout and configured branch' do
    task_id
    other_project_path = File.join(root_path, 'other-project')
    initialize_git_project(other_project_path)

    expect do
      service_class.call(task_path: task_path, project_path: other_project_path)
    end.to raise_error(
      "Task #{task_id} checkout mismatch: expected #{File.realpath(project_path)}, " \
      "got #{File.realpath(other_project_path)}"
    )

    git!('checkout', '-q', '-b', 'other')
    expect do
      service_class.call(task_path: task_path, project_path: project_path)
    end.to raise_error("Task #{task_id} branch mismatch: expected feature, got other")
  end

  it 'uses Task config as the branch authority' do
    task_id
    write_config(branch_name: 'other')

    expect do
      service_class.call(task_path: task_path, project_path: project_path)
    end.to raise_error("Task #{task_id} branch mismatch: expected other, got feature")
  end

  private

  def db
    Database.connection
  end

  def insert_task
    db[:tasks].insert(
      created_at: Time.now,
      task_path: File.realpath(task_path),
      project_path: File.realpath(project_path),
      starting_commit_sha: head_sha,
      state: 'final_checks_passed',
      super_review_agent: 'claude'
    )
  end

  def write_task_files
    FileUtils.mkdir_p(task_path)
    File.write(File.join(task_path, 'task.md'), "# Context\n")
    File.write(File.join(task_path, 'steps.md'), "# Steps\n\n## Step 1: Start\n")
    write_config
  end

  def write_config(branch_name: 'feature')
    File.write(
      File.join(task_path, 'config.json'),
      JSON.generate(
        'branch' => {
          'name' => branch_name,
          'original_base_ref' => 'main',
          'original_base_commit_sha' => head_sha,
          'active_base_ref' => 'main',
          'active_base_commit_sha' => head_sha
        }
      )
    )
  end

  def initialize_git_project(path = project_path)
    FileUtils.mkdir_p(path)
    git!('init', '-q', '--initial-branch=main', path: path)
    git!('config', 'user.email', 'task@example.com', path: path)
    git!('config', 'user.name', 'Task', path: path)
    File.write(File.join(path, 'tracked.txt'), "initial\n")
    git!('add', 'tracked.txt', path: path)
    git!('commit', '-q', '-m', 'Initial', path: path)
    git!('checkout', '-q', '-b', 'feature', path: path)
  end

  def head_sha
    git!('rev-parse', 'HEAD').strip
  end

  def git!(*arguments, path: project_path)
    stdout, stderr, status = Open3.capture3('git', '-C', path, *arguments)
    raise stderr unless status.success?

    stdout
  end
end
