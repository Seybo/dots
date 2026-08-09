# frozen_string_literal: true

require 'fileutils'
require 'open3'
require 'tmpdir'
require_relative '../../spec/spec_helper'

RSpec.describe 'Autofix Task rebasing' do
  let(:db) { Database.connection }
  let(:root_path) { Dir.mktmpdir('autofix-rebase-task-spec') }
  let(:paths) do
    {
      origin: File.join(root_path, 'origin.git'),
      project: File.join(root_path, 'project'),
      updater: File.join(root_path, 'updater')
    }
  end
  let(:repository_shas) { setup_repository }
  let(:review_id) { insert_review }

  before do
    repository_shas
    review_id
    db[:tasks].update(starting_commit_sha: base_sha)
  end

  after do
    FileUtils.remove_entry(root_path)
  end

  it 'rebases a completed Task before a Review exists' do
    db[:reviews].where(id: review_id).delete
    target_sha = advance_main

    result = RebaseAutofixTask.call(task_path: task_path, project_path: project_path)

    expect(result).to eq(
      "Task #{task_id} rebased.\n" \
      "Active base: origin/main @ #{base_sha} -> origin/main @ #{target_sha}\n" \
      "Task starting commit: #{base_sha} -> #{target_sha}\n" \
      'Push: not performed.'
    )
    expect(task).to include(starting_commit_sha: target_sha, state: 'final_checks_passed')
    expect(branch_config).to include(
      'original_base_ref' => 'origin/main',
      'original_base_commit_sha' => base_sha,
      'active_base_ref' => 'origin/main',
      'active_base_commit_sha' => target_sha
    )
    expect(remote_branch?('feature')).to be(false)
  end

  it 'remaps distinct Task and active Review boundaries without prior Autofix implementation' do
    target_sha = advance_main
    original_config = branch_config

    result = RebaseAutofixTask.call(task_path: task_path, project_path: project_path)
    new_review_start = git!('rev-parse', 'HEAD~2').strip

    expect(result).to eq(
      "Task #{task_id} rebased.\n" \
      "Review: 1\n" \
      "Active base: origin/main @ #{base_sha} -> origin/main @ #{target_sha}\n" \
      "Task starting commit: #{base_sha} -> #{target_sha}\n" \
      "Review starting commit: #{review_starting_sha} -> #{new_review_start}\n" \
      'Push: not performed.'
    )
    expect(task).to include(starting_commit_sha: target_sha, state: 'final_checks_passed')
    expect(review).to include(starting_commit_sha: new_review_start, state: 'manager_issues_assessment')
    expect(db[:work_cycles].where(review_id: review_id).count).to eq(0)
    expect(branch_config).to include(
      'original_base_ref' => original_config.fetch('original_base_ref'),
      'original_base_commit_sha' => original_config.fetch('original_base_commit_sha'),
      'active_base_ref' => 'origin/main',
      'active_base_commit_sha' => target_sha
    )
    expect(git!('branch', '--show-current').strip).to eq('feature')
    expect(remote_branch?('feature')).to be(false)
  end

  it 'leaves normal Review resume explicit and stable after rebasing' do
    issue_id = db[:reported_issues].insert(
      created_at: Time.now,
      source: 'local',
      body: 'Resume this issue.',
      decision: nil,
      project_path: File.realpath(project_path)
    )
    db[:review_issues].insert(
      created_at: Time.now,
      review_id: review_id,
      reported_issue_id: issue_id
    )
    advance_main

    rebase_output = RebaseAutofixTask.call(task_path: task_path, project_path: project_path)

    expect(rebase_output).not_to include('Issue:')
    expect(db[:work_cycles].where(review_id: review_id).count).to eq(0)
    expect(ResumeReview.call(task_id: task_id)).to eq(
      "Issue: #{issue_id}\n\n> Resume this issue."
    )
  end

  it 'preserves completed workflow data while rebasing an active Review' do
    issue_id = db[:reported_issues].insert(
      created_at: Time.now,
      source: 'local',
      body: 'Settled issue.',
      decision: 'skipped',
      project_path: File.realpath(project_path)
    )
    db[:review_issues].insert(
      created_at: Time.now,
      review_id: review_id,
      reported_issue_id: issue_id
    )
    work_cycle_id = insert_completed_work_cycle
    data_before = {
      work_cycle: db[:work_cycles].where(id: work_cycle_id).first,
      issue: db[:reported_issues].where(id: issue_id).first,
      relationship: db[:review_issues].where(review_id: review_id, reported_issue_id: issue_id).first
    }
    advance_main

    RebaseAutofixTask.call(task_path: task_path, project_path: project_path)

    expect(db[:work_cycles].where(id: work_cycle_id).first).to eq(data_before.fetch(:work_cycle))
    expect(db[:reported_issues].where(id: issue_id).first).to eq(data_before.fetch(:issue))
    expect(db[:review_issues].where(review_id: review_id, reported_issue_id: issue_id).first).
      to eq(data_before.fetch(:relationship))
  end

  it 'preserves an explicit different base ref exactly' do
    target_sha = create_release_branch

    result = RebaseAutofixTask.call(
      task_path: task_path,
      project_path: project_path,
      base_ref: 'origin/release'
    )

    expect(result).to include(
      "Active base: origin/main @ #{base_sha} -> origin/release @ #{target_sha}",
      "Task starting commit: #{base_sha} -> #{target_sha}"
    )
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

    result = RebaseAutofixTask.call(
      task_path: task_path,
      project_path: project_path,
      base_ref: 'origin/same'
    )

    expect(result).to include(
      "Active base: origin/main @ #{base_sha} -> origin/same @ #{base_sha}",
      "Task starting commit: #{base_sha} -> #{base_sha}",
      "Review starting commit: #{review_starting_sha} -> #{review_starting_sha}"
    )
    expect(git!('rev-parse', 'HEAD').strip).to eq(original_head)
    expect(task.fetch(:starting_commit_sha)).to eq(base_sha)
    expect(review.fetch(:starting_commit_sha)).to eq(review_starting_sha)
    expect(branch_config).to include(
      'original_base_ref' => 'origin/main',
      'active_base_ref' => 'origin/same',
      'active_base_commit_sha' => base_sha
    )
  end

  it 'leaves all metadata unchanged across repeated conflicts and updates it on success' do
    target_sha = advance_main(is_conflicting: true)
    task_before = task
    review_before = review
    config_before = branch_config

    result = RebaseAutofixTask.call(task_path: task_path, project_path: project_path)

    expect(result).to eq(conflict_control(target_sha))
    expect(task).to eq(task_before)
    expect(review).to eq(review_before)
    expect(branch_config).to eq(config_before)
    expect(unmerged_paths).to eq(['one.txt'])

    File.write(File.join(project_path, 'one.txt'), "resolved one\n")
    result = continue_rebase(target_sha)

    expect(result).to eq(conflict_control(target_sha))
    expect(task).to eq(task_before)
    expect(review).to eq(review_before)
    expect(branch_config).to eq(config_before)
    expect(unmerged_paths).to eq(['two.txt'])

    File.write(File.join(project_path, 'two.txt'), "resolved two\n")
    result = continue_rebase(target_sha)
    new_review_start = git!('rev-parse', 'HEAD~2').strip

    expect(result).to include(
      "Task #{task_id} rebased.",
      'Review: 1',
      "Task starting commit: #{base_sha} -> #{target_sha}",
      "Review starting commit: #{review_starting_sha} -> #{new_review_start}",
      'Push: not performed.'
    )
    expect(task.fetch(:starting_commit_sha)).to eq(target_sha)
    expect(review.fetch(:starting_commit_sha)).to eq(new_review_start)
    expect(branch_config.fetch('active_base_commit_sha')).to eq(target_sha)
    expect(rebase_in_progress?).to be(false)
  end

  it 'supports manual abort and a fresh explicit restart without pending state' do
    target_sha = advance_main(is_conflicting: true)
    config_before = branch_config

    expect(RebaseAutofixTask.call(task_path: task_path, project_path: project_path)).
      to eq(conflict_control(target_sha))
    git!('rebase', '--abort')
    expect(task.fetch(:starting_commit_sha)).to eq(base_sha)
    expect(review.fetch(:starting_commit_sha)).to eq(review_starting_sha)
    expect(branch_config).to eq(config_before)

    expect(RebaseAutofixTask.call(task_path: task_path, project_path: project_path)).
      to eq(conflict_control(target_sha))
  end

  it 'rejects continuation when retained target metadata does not match Git' do
    advance_main(is_conflicting: true)
    RebaseAutofixTask.call(task_path: task_path, project_path: project_path)
    File.write(File.join(project_path, 'one.txt'), "resolved one\n")

    expect do
      ContinueAutofixRebase.call(
        task_path: task_path,
        project_path: project_path,
        target_base_ref: 'origin/main',
        target_base_commit_sha: base_sha
      )
    end.to raise_error(/Rebase target .* does not match retained target #{base_sha}/)
    expect(task.fetch(:starting_commit_sha)).to eq(base_sha)
    expect(review.fetch(:starting_commit_sha)).to eq(review_starting_sha)
  end

  private

  def origin_path
    paths.fetch(:origin)
  end

  def project_path
    paths.fetch(:project)
  end

  def updater_path
    paths.fetch(:updater)
  end

  def base_sha
    repository_shas.fetch(:base_sha)
  end

  def review_starting_sha
    repository_shas.fetch(:review_starting_sha)
  end

  def task_id
    task.fetch(:id)
  end

  def task_path
    task.fetch(:task_path)
  end

  def setup_repository
    git_without_path!('init', '--bare', '-q', '--initial-branch=main', origin_path)
    git_without_path!('init', '-q', '--initial-branch=main', project_path)
    configure_git(project_path)
    File.write(File.join(project_path, 'one.txt'), "base one\n")
    File.write(File.join(project_path, 'two.txt'), "base two\n")
    git!('add', '-A')
    git!('commit', '-q', '-m', 'Base')
    base_sha = git!('rev-parse', 'HEAD').strip
    git!('remote', 'add', 'origin', origin_path)
    git!('push', '-q', '-u', 'origin', 'main')
    git!('checkout', '-q', '-b', 'feature')
    File.write(File.join(project_path, 'task.txt'), "implemented\n")
    git!('add', 'task.txt')
    git!('commit', '-q', '-m', 'Autoimplement Task')
    review_starting_sha = git!('rev-parse', 'HEAD').strip
    File.write(File.join(project_path, 'one.txt'), "feature one\n")
    git!('add', 'one.txt')
    git!('commit', '-q', '-m', 'Autofix one')
    File.write(File.join(project_path, 'two.txt'), "feature two\n")
    git!('add', 'two.txt')
    git!('commit', '-q', '-m', 'Autofix two')

    { base_sha: base_sha, review_starting_sha: review_starting_sha }
  end

  def advance_main(is_conflicting: false)
    prepare_updater
    File.write(File.join(updater_path, 'base.txt'), "advanced\n")
    if is_conflicting
      File.write(File.join(updater_path, 'one.txt'), "main one\n")
      File.write(File.join(updater_path, 'two.txt'), "main two\n")
    end
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
    git_in_updater!('commit', '-q', '-m', 'Create release')
    git_in_updater!('push', '-q', 'origin', 'release')
    git_in_updater!('rev-parse', 'HEAD').strip
  end

  def prepare_updater
    return if Dir.exist?(updater_path)

    git_without_path!('clone', '-q', origin_path, updater_path)
    configure_git(updater_path)
  end

  def configure_git(path)
    git_at_path!(path, 'config', 'user.email', 'autofix@example.com')
    git_at_path!(path, 'config', 'user.name', 'Autofix')
    git_at_path!(path, 'config', 'rerere.enabled', 'false')
    git_at_path!(path, 'config', 'rebase.autoStash', 'false')
  end

  def insert_review
    ReviewFactory.insert(
      project_path: File.realpath(project_path),
      branch_name: 'feature',
      starting_commit_sha: review_starting_sha,
      base_ref: 'origin/main',
      base_commit_sha: base_sha,
      state: 'manager_issues_assessment'
    )
  end

  def insert_completed_work_cycle
    db[:work_cycles].insert(
      created_at: Time.now,
      completed_at: Time.now,
      review_id: review_id,
      role: 'reviewer',
      action: 'review',
      provider: nil,
      model: nil,
      reasoning_level: nil
    )
  end

  def task
    db[:tasks].where(id: db[:reviews].where(id: review_id).get(:task_id)).first || db[:tasks].first
  end

  def review
    db[:reviews].where(id: review_id).first
  end

  def branch_config
    ReadTaskConfig.call(task_path: task_path).fetch('branch')
  end

  def continue_rebase(target_sha)
    ContinueAutofixRebase.call(
      task_path: task_path,
      project_path: project_path,
      target_base_ref: 'origin/main',
      target_base_commit_sha: target_sha
    )
  end

  def conflict_control(target_sha)
    "AutoFixRebaseConflict #{task_id}\n" \
      "RebaseTargetRef origin/main\n" \
      "RebaseTargetCommit #{target_sha}"
  end

  def unmerged_paths
    git!('diff', '--name-only', '--diff-filter=U').lines(chomp: true)
  end

  def rebase_in_progress?
    Dir.exist?(File.join(git_directory, 'rebase-merge'))
  end

  def git_directory
    git!('rev-parse', '--absolute-git-dir').strip
  end

  def remote_branch?(branch_name)
    _stdout, _stderr, status = Open3.capture3(
      'git', '--git-dir', origin_path, 'show-ref', '--verify', "refs/heads/#{branch_name}"
    )
    status.success?
  end

  def git!(*arguments)
    git_at_path!(project_path, *arguments)
  end

  def git_in_updater!(*arguments)
    git_at_path!(updater_path, *arguments)
  end

  def git_at_path!(path, *arguments)
    stdout, stderr, status = Open3.capture3('git', '-C', path, *arguments)
    raise stderr unless status.success?

    stdout
  end

  def git_without_path!(*arguments)
    stdout, stderr, status = Open3.capture3('git', *arguments)
    raise stderr unless status.success?

    stdout
  end
end
