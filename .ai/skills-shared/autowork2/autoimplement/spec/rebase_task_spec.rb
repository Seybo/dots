# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'open3'
require 'tmpdir'
require_relative '../../spec/spec_helper'

RSpec.describe 'Autoimplement Task rebasing' do
  let(:root_path) { Dir.mktmpdir('autoimplement-rebase-task-spec') }
  let(:project_path) { File.join(root_path, 'project') }
  let(:base_sha) { setup_repository }
  let(:task_id) { insert_task }

  before do
    base_sha
    write_task_files
    task_id
  end

  after do
    FileUtils.remove_entry(root_path)
  end

  it 'rebases before Step 1 without requiring a completed Work Cycle' do
    target_sha = advance_main

    output = RebaseTask.call(task_path: task_path, project_path: project_path)

    expect(output).to eq(
      "Task #{task_id} rebased.\n" \
      "Active base: origin/main @ #{base_sha} -> origin/main @ #{target_sha}\n" \
      "Starting commit: #{base_sha} -> #{target_sha}\n" \
      'Push: not performed.'
    )
    expect(task).to include(starting_commit_sha: target_sha, state: 'initialized')
    expect(branch_config).to include(
      'original_base_commit_sha' => base_sha,
      'active_base_ref' => 'origin/main',
      'active_base_commit_sha' => target_sha
    )
    expect(remote_branch?('feature')).to be(false)
  end

  it 'rebases between completed Work Cycles without changing accepted workflow data' do
    add_task_commit('feature.txt', "feature\n")
    work_cycle_id = insert_work_cycle(completed_at: Time.now)
    issue_id = insert_issue
    decision = db[:reported_issues].where(id: issue_id).update(decision: 'approved')
    target_sha = advance_main

    RebaseTask.call(task_path: task_path, project_path: project_path)

    expect(git!('rev-list', '--count', "#{target_sha}..HEAD").strip).to eq('1')
    expect(db[:work_cycles].where(id: work_cycle_id).first).to include(completed_at: be_a(Time))
    expect(db[:reported_issues].where(id: issue_id).first).to include(decision: 'approved')
    expect(decision).to eq(1)
  end

  it 'preserves an explicit different base ref exactly' do
    add_task_commit('feature.txt', "feature\n")
    target_sha = create_release_branch

    output = RebaseTask.call(
      task_path: task_path,
      project_path: project_path,
      base_ref: 'origin/release'
    )

    expect(output).to include("origin/main @ #{base_sha} -> origin/release @ #{target_sha}")
    expect(branch_config).to include(
      'original_base_ref' => 'origin/main',
      'original_base_commit_sha' => base_sha,
      'active_base_ref' => 'origin/release',
      'active_base_commit_sha' => target_sha
    )
  end

  it 'updates only the ref when an explicit target resolves to the active SHA' do
    git!('push', '-q', 'origin', 'main:refs/heads/same')
    original_head = git!('rev-parse', 'HEAD').strip

    output = RebaseTask.call(
      task_path: task_path,
      project_path: project_path,
      base_ref: 'origin/same'
    )

    expect(output).to include("origin/main @ #{base_sha} -> origin/same @ #{base_sha}")
    expect(git!('rev-parse', 'HEAD').strip).to eq(original_head)
    expect(task.fetch(:starting_commit_sha)).to eq(base_sha)
    expect(branch_config).to include(
      'original_base_ref' => 'origin/main',
      'active_base_ref' => 'origin/same',
      'active_base_commit_sha' => base_sha
    )
  end

  it 'leaves Task metadata unchanged across a conflict and completes after continuation' do
    add_task_commit('conflict.txt', "feature\n")
    target_sha = advance_main(conflict: true)
    task_before = task
    config_before = branch_config

    output = RebaseTask.call(task_path: task_path, project_path: project_path)

    expect(output).to eq(
      "AutoImplementRebaseConflict #{task_id}\n" \
      "RebaseTargetRef origin/main\n" \
      "RebaseTargetCommit #{target_sha}"
    )
    expect(task).to eq(task_before)
    expect(branch_config).to eq(config_before)

    File.write(File.join(project_path, 'conflict.txt'), "resolved\n")
    output = ContinueTaskRebase.call(
      task_path: task_path,
      project_path: project_path,
      target_base_ref: 'origin/main',
      target_base_commit_sha: target_sha
    )

    expect(output).to include("Task #{task_id} rebased.", "Starting commit: #{base_sha} -> #{target_sha}")
    expect(task.fetch(:starting_commit_sha)).to eq(target_sha)
    expect(branch_config.fetch('active_base_commit_sha')).to eq(target_sha)
    expect(rebase_in_progress?).to be(false)
  end

  it 'rejects dirty, wrong-branch, incomplete-Work-Cycle, and final-review states before mutation' do
    File.write(File.join(project_path, 'dirty.txt'), "dirty\n")
    expect { rebase }.to raise_error(/Working tree is not clean/)
    File.delete(File.join(project_path, 'dirty.txt'))

    git!('checkout', '-q', 'main')
    expect { rebase }.to raise_error(/Current branch main does not match configured branch feature/)
    git!('checkout', '-q', 'feature')

    work_cycle_id = insert_work_cycle(completed_at: nil)
    expect { rebase }.to raise_error("Task #{task_id} has incomplete Work Cycle #{work_cycle_id}")
    db[:work_cycles].where(id: work_cycle_id).delete

    db[:tasks].where(id: task_id).update(state: 'super_review')
    expect { rebase }.to raise_error("Task #{task_id} cannot rebase from state super_review")
  end

  it 'rejects invalid target and starting-boundary ancestry before mutation' do
    expect do
      RebaseTask.call(task_path: task_path, project_path: project_path, base_ref: 'origin/missing')
    end.to raise_error(%r{git .* rev-parse origin/missing\^\{commit\} failed})

    unrelated_sha = create_unrelated_commit
    db[:tasks].where(id: task_id).update(starting_commit_sha: unrelated_sha)
    expect { rebase }.to raise_error(/merge-base --is-ancestor #{unrelated_sha}/)

    db[:tasks].where(id: task_id).update(starting_commit_sha: base_sha)
    UpdateTaskConfig.call(
      task_path: task_path,
      active_base_ref: 'unrelated',
      active_base_commit_sha: unrelated_sha
    )
    expect { rebase }.to raise_error(/merge-base --is-ancestor #{unrelated_sha}/)
  end

  it 'rejects local-provider configuration and an existing Git rebase' do
    write_config(
      name: 'main',
      original_ref: base_sha,
      original_sha: base_sha,
      active_ref: base_sha,
      active_sha: base_sha
    )
    expect { rebase }.to raise_error('Local Tasks cannot be rebased')

    write_config
    add_task_commit('conflict.txt', "feature\n")
    advance_main(conflict: true)
    rebase
    expect { rebase }.to raise_error(
      'A Git rebase is already in progress; run git rebase --abort before starting again'
    )
  end

  private

  def db
    Database.connection
  end

  def origin_path
    File.join(root_path, 'origin.git')
  end

  def updater_path
    File.join(root_path, 'updater')
  end

  def task_path
    File.join(root_path, 'task')
  end

  def setup_repository
    git_global!('init', '--bare', '-q', '--initial-branch=main', origin_path)
    git_global!('init', '-q', '--initial-branch=main', project_path)
    configure_git(project_path)
    File.write(File.join(project_path, 'base.txt'), "base\n")
    File.write(File.join(project_path, 'conflict.txt'), "base\n")
    git!('add', '-A')
    git!('commit', '-q', '-m', 'Base')
    sha = git!('rev-parse', 'HEAD').strip
    git!('remote', 'add', 'origin', origin_path)
    git!('push', '-q', '-u', 'origin', 'main')
    git!('checkout', '-q', '-b', 'feature')
    sha
  end

  def write_task_files
    FileUtils.mkdir_p(task_path)
    File.write(File.join(task_path, 'task.md'), "# Task\n")
    File.write(File.join(task_path, 'steps.md'), "# Steps\n\n## Step 1: Implement\n")
    write_config
  end

  def write_config(
    name: 'feature',
    original_ref: 'origin/main',
    original_sha: base_sha,
    active_ref: 'origin/main',
    active_sha: base_sha
  )
    File.write(
      File.join(task_path, 'config.json'),
      JSON.generate(
        'branch' => {
          'name' => name,
          'original_base_ref' => original_ref,
          'original_base_commit_sha' => original_sha,
          'active_base_ref' => active_ref,
          'active_base_commit_sha' => active_sha
        }
      )
    )
  end

  def insert_task
    db[:tasks].insert(
      created_at: Time.now,
      task_path: File.realpath(task_path),
      project_path: File.realpath(project_path),
      starting_commit_sha: base_sha,
      state: 'initialized',
      super_review_agent: 'claude'
    )
  end

  def insert_work_cycle(completed_at:)
    db[:work_cycles].insert(
      created_at: Time.now,
      completed_at: completed_at,
      task_id: task_id,
      step_number: 1,
      role: 'worker',
      action: 'implementation'
    )
  end

  def insert_issue
    db[:reported_issues].insert(
      created_at: Time.now,
      project_path: File.realpath(project_path),
      source: 'reviewer',
      body: 'Keep this issue.'
    )
  end

  def task
    db[:tasks].where(id: task_id).first
  end

  def branch_config
    ReadTaskConfig.call(task_path: task_path).fetch('branch')
  end

  def rebase
    RebaseTask.call(task_path: task_path, project_path: project_path)
  end

  def add_task_commit(path, content)
    File.write(File.join(project_path, path), content)
    git!('add', path)
    git!('commit', '-q', '-m', 'Task work')
  end

  def advance_main(conflict: false)
    prepare_updater
    File.write(File.join(updater_path, 'base.txt'), "advanced\n")
    File.write(File.join(updater_path, 'conflict.txt'), "main\n") if conflict
    git_in_updater!('add', '-A')
    git_in_updater!('commit', '-q', '-m', 'Advance main')
    git_in_updater!('push', '-q', 'origin', 'main')
    git_in_updater!('rev-parse', 'HEAD').strip
  end

  def create_release_branch
    prepare_updater
    git_in_updater!('checkout', '-q', '-b', 'release')
    File.write(File.join(updater_path, 'release.txt'), "release\n")
    git_in_updater!('add', 'release.txt')
    git_in_updater!('commit', '-q', '-m', 'Release base')
    git_in_updater!('push', '-q', 'origin', 'release')
    git_in_updater!('rev-parse', 'HEAD').strip
  end

  def create_unrelated_commit
    prepare_updater
    git_in_updater!('checkout', '-q', '--orphan', 'unrelated')
    git_in_updater!('rm', '-q', '-rf', '.')
    File.write(File.join(updater_path, 'unrelated.txt'), "unrelated\n")
    git_in_updater!('add', 'unrelated.txt')
    git_in_updater!('commit', '-q', '-m', 'Unrelated')
    git_in_updater!('rev-parse', 'HEAD').strip
  end

  def prepare_updater
    return if Dir.exist?(updater_path)

    git_global!('clone', '-q', origin_path, updater_path)
    configure_git(updater_path)
  end

  def configure_git(path)
    git_at!(path, 'config', 'user.email', 'autoimplement@example.com')
    git_at!(path, 'config', 'user.name', 'Autoimplement')
    git_at!(path, 'config', 'rerere.enabled', 'false')
    git_at!(path, 'config', 'rebase.autoStash', 'false')
  end

  def remote_branch?(branch_name)
    _stdout, _stderr, status = Open3.capture3(
      'git', '--git-dir', origin_path, 'show-ref', '--verify', "refs/heads/#{branch_name}"
    )
    status.success?
  end

  def rebase_in_progress?
    git_directory = git!('rev-parse', '--absolute-git-dir').strip
    %w[rebase-merge rebase-apply].any? { |name| Dir.exist?(File.join(git_directory, name)) }
  end

  def git!(*arguments)
    git_at!(project_path, *arguments)
  end

  def git_in_updater!(*arguments)
    git_at!(updater_path, *arguments)
  end

  def git_at!(path, *arguments)
    stdout, stderr, status = Open3.capture3('git', '-C', path, *arguments)
    raise stderr unless status.success?

    stdout
  end

  def git_global!(*arguments)
    stdout, stderr, status = Open3.capture3('git', *arguments)
    raise stderr unless status.success?

    stdout
  end
end
