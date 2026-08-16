# frozen_string_literal: true

require 'fileutils'
require 'open3'
require 'tmpdir'
require_relative '../../spec/spec_helper'

RSpec.describe SquashTask do
  let(:project_path) { Dir.mktmpdir('autoimplement-squash-task-spec') }
  let(:other_path) { Dir.mktmpdir('autoimplement-squash-other-spec') }
  let(:task_path) { Dir.mktmpdir('autoimplement-squash-task-files-spec') }
  let(:starting_commit_sha) { git!('rev-parse', 'HEAD').strip }
  let(:task_id) do
    db[:tasks].insert(
      created_at: Time.now,
      task_path: task_path,
      project_path: project_path,
      starting_commit_sha: starting_commit_sha,
      state: 'final_checks_passed'
    )
  end

  before do
    git!('init', '-q')
    git!('config', 'user.email', 'autoimplement@example.com')
    git!('config', 'user.name', 'Autoimplement')
    File.write(File.join(project_path, 'tracked.txt'), "initial\n")
    git!('add', 'tracked.txt')
    git!('commit', '-q', '-m', 'Initial commit')
    File.write(File.join(task_path, 'task.md'), "# Task\n")
    File.write(
      File.join(task_path, 'config.json'),
      JSON.generate(
        'branch' => {
          'name' => git!('branch', '--show-current').strip,
          'original_base_ref' => 'origin/main',
          'original_base_commit_sha' => starting_commit_sha,
          'active_base_ref' => 'origin/main',
          'active_base_commit_sha' => starting_commit_sha
        }
      )
    )
  end

  after do
    FileUtils.remove_entry(project_path)
    FileUtils.remove_entry(other_path)
    FileUtils.remove_entry(task_path)
  end

  it 'squashes the actual completed Task range with the supplied subject' do
    task_id
    File.write(File.join(project_path, 'tracked.txt'), "implemented\n")
    git!('add', 'tracked.txt')
    git!('commit', '-q', '-m', 'Unexpected-looking but accepted history')
    File.write(File.join(project_path, 'extra.txt'), "more work\n")
    git!('add', 'extra.txt')
    git!('commit', '-q', '-m', 'Another arbitrary subject')
    expected_tree_sha = git!('rev-parse', 'HEAD^{tree}').strip
    task_before_squash = task

    output = described_class.call(
      task_id: task_id,
      project_path: project_path,
      subject: 'Current Shortcut story name'
    )
    final_commit_sha = git!('rev-parse', 'HEAD').strip

    expect(output).to eq(
      "Task #{task_id} squashed locally.\n" \
      "Final commit: #{final_commit_sha} Current Shortcut story name\n" \
      'Push: not performed.'
    )
    expect(git!('log', '-1', '--format=%s').strip).to eq('Current Shortcut story name')
    expect(git!('rev-parse', 'HEAD^').strip).to eq(starting_commit_sha)
    expect(git!('rev-parse', 'HEAD^{tree}').strip).to eq(expected_tree_sha)
    expect(git!('status', '--porcelain')).to eq('')
    expect(task).to eq(task_before_squash)
  end

  it 'refuses a Task that is not durably completed' do
    task_id
    db[:tasks].where(id: task_id).update(state: 'manager_review')
    head_before_squash = git!('rev-parse', 'HEAD').strip

    expect do
      described_class.call(task_id: task_id, project_path: project_path, subject: 'Task subject')
    end.to raise_error(RuntimeError, "Task #{task_id} is not completed")

    expect(git!('rev-parse', 'HEAD').strip).to eq(head_before_squash)
  end

  it 'refuses another checkout' do
    task_id
    head_before_squash = git!('rev-parse', 'HEAD').strip

    expect do
      described_class.call(task_id: task_id, project_path: other_path, subject: 'Task subject')
    end.to raise_error(RuntimeError, "Task #{task_id} belongs to another project")

    expect(git!('rev-parse', 'HEAD').strip).to eq(head_before_squash)
  end

  it 'refuses a dirty tree without changing completed state' do
    task_before_squash = task
    head_before_squash = git!('rev-parse', 'HEAD').strip
    File.write(File.join(project_path, 'tracked.txt'), "dirty\n")

    expect do
      described_class.call(task_id: task_id, project_path: project_path, subject: 'Task subject')
    end.to raise_error(RuntimeError, /Working tree is not clean/)

    expect(task).to eq(task_before_squash)
    expect(git!('rev-parse', 'HEAD').strip).to eq(head_before_squash)
  end

  it 'refuses a starting commit outside HEAD ancestry' do
    tree_sha = git!('rev-parse', 'HEAD^{tree}').strip
    unrelated_sha = git!('commit-tree', tree_sha, '-m', 'Unrelated root').strip
    task_id
    db[:tasks].where(id: task_id).update(starting_commit_sha: unrelated_sha)
    head_before_squash = git!('rev-parse', 'HEAD').strip

    expect do
      described_class.call(task_id: task_id, project_path: project_path, subject: 'Task subject')
    end.to raise_error(
      RuntimeError,
      "Task #{task_id} starting commit #{unrelated_sha} is not an ancestor of HEAD"
    )

    expect(git!('rev-parse', 'HEAD').strip).to eq(head_before_squash)
  end

  it 'refuses an empty subject before inspecting or changing Git' do
    head_before_squash = git!('rev-parse', 'HEAD').strip
    allow(ValidateCleanGitState).to receive(:call).and_raise('should not run')

    expect do
      described_class.call(task_id: task_id, project_path: project_path, subject: '  ')
    end.to raise_error(ArgumentError, 'Squash subject cannot be empty')

    expect(git!('rev-parse', 'HEAD').strip).to eq(head_before_squash)
  end

  private

  def task
    db[:tasks].where(id: task_id).first
  end

  def db
    Database.connection
  end

  def git!(*arguments)
    stdout, stderr, status = Open3.capture3('git', '-C', project_path, *arguments)
    raise stderr unless status.success?

    stdout
  end
end
