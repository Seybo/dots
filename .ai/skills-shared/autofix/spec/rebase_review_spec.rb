# frozen_string_literal: true

require 'fileutils'
require 'open3'
require 'tmpdir'
require_relative 'spec_helper'

RSpec.describe 'Review rebasing' do
  let(:db) { Database.connection }
  let(:root_path) { Dir.mktmpdir('autofix-rebase-review-spec') }
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
    2.times { insert_completed_implementation }
  end

  after do
    FileUtils.remove_entry(root_path)
  end

  it 'rebases onto an advanced version of the active base and updates mutable metadata' do
    target_sha = advance_main
    original_review = review

    result = RebaseReview.call(project_path: project_path, branch_name: 'feature')

    expect(result).to eq(
      "Review 1 rebased.\n" \
      "Active base: origin/main @ #{base_sha} -> origin/main @ #{target_sha}\n" \
      "Starting commit: #{starting_sha} -> #{target_sha}"
    )
    expect(review).to include(
      starting_commit_sha: target_sha,
      original_base_ref: original_review.fetch(:original_base_ref),
      original_base_commit_sha: original_review.fetch(:original_base_commit_sha),
      active_base_ref: 'origin/main',
      active_base_commit_sha: target_sha,
      state: 'reviewer_review'
    )
    expect(git!('branch', '--show-current').strip).to eq('feature')
    expect(git!('rev-list', '--count', "#{target_sha}..HEAD").strip).to eq('2')
    expect(remote_sha('main')).to eq(target_sha)
    expect(remote_branch?('feature')).to be(false)
  end

  it 'rebases onto a different explicit base without rewriting its ref' do
    target_sha = create_release_branch

    result = RebaseReview.call(
      project_path: project_path,
      branch_name: 'feature',
      base_ref: 'origin/release'
    )

    expect(result).to include(
      "Active base: origin/main @ #{base_sha} -> origin/release @ #{target_sha}",
      "Starting commit: #{starting_sha} -> #{target_sha}"
    )
    expect(review).to include(
      original_base_ref: 'origin/main',
      original_base_commit_sha: base_sha,
      active_base_ref: 'origin/release',
      active_base_commit_sha: target_sha,
      starting_commit_sha: target_sha,
      state: 'reviewer_review'
    )
    expect(git!('branch', '--show-current').strip).to eq('feature')
    expect(remote_sha('release')).to eq(target_sha)
  end

  it 'preserves metadata across repeated conflicts and updates it after final continuation' do
    target_sha = advance_main(is_conflicting: true)
    review_before = review

    result = RebaseReview.call(project_path: project_path, branch_name: 'feature')

    expect(result).to eq(conflict_control(target_sha))
    expect(review).to eq(review_before)
    expect(unmerged_paths).to eq(['one.txt'])

    File.write(File.join(project_path, 'one.txt'), "resolved one\n")
    result = continue_rebase(target_sha)

    expect(result).to eq(conflict_control(target_sha))
    expect(review).to eq(review_before)
    expect(unmerged_paths).to eq(['two.txt'])

    File.write(File.join(project_path, 'two.txt'), "resolved two\n")
    result = continue_rebase(target_sha)

    expect(result).to include(
      "Review 1 rebased.\n",
      "Active base: origin/main @ #{base_sha} -> origin/main @ #{target_sha}",
      "Starting commit: #{starting_sha} -> #{target_sha}"
    )
    expect(review).to include(
      active_base_ref: 'origin/main',
      active_base_commit_sha: target_sha,
      starting_commit_sha: target_sha,
      state: 'reviewer_review'
    )
    expect(rebase_in_progress?).to be(false)
    expect(git!('status', '--porcelain')).to be_empty
  end

  it 'rejects a new start while the same rebase is in progress' do
    target_sha = advance_main(is_conflicting: true)
    RebaseReview.call(project_path: project_path, branch_name: 'feature')
    review_before = review

    expect do
      RebaseReview.call(project_path: project_path, branch_name: 'feature')
    end.to raise_error('A Git rebase is already in progress; run git rebase --abort before starting again')
    expect(review).to eq(review_before)
    expect(unmerged_paths).to eq(['one.txt'])
    expect(rebase_onto_sha).to eq(target_sha)
  end

  it 'rejects continuation when the retained target SHA does not match the in-progress rebase' do
    advance_main(is_conflicting: true)
    RebaseReview.call(project_path: project_path, branch_name: 'feature')
    File.write(File.join(project_path, 'one.txt'), "resolved one\n")

    expect do
      ContinueReviewRebase.call(
        project_path: project_path,
        branch_name: 'feature',
        target_base_ref: 'origin/main',
        target_base_commit_sha: base_sha
      )
    end.to raise_error(/Rebase target .* does not match retained target #{base_sha}/)
    expect(unmerged_paths).to eq(['one.txt'])
    expect(review).to include(active_base_commit_sha: base_sha, starting_commit_sha: starting_sha)
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

  def starting_sha
    repository_shas.fetch(:starting_sha)
  end

  def setup_repository
    git_without_path!('init', '--bare', '-q', '--initial-branch=main', origin_path)
    git_without_path!('init', '-q', '--initial-branch=main', project_path)
    configure_git(project_path)
    File.write(File.join(project_path, 'base.txt'), "base\n")
    File.write(File.join(project_path, 'one.txt'), "base one\n")
    File.write(File.join(project_path, 'two.txt'), "base two\n")
    git!('add', '-A')
    git!('commit', '-q', '-m', 'Base')
    base_sha = git!('rev-parse', 'HEAD').strip
    git!('remote', 'add', 'origin', origin_path)
    git!('push', '-q', '-u', 'origin', 'main')
    git!('checkout', '-q', '-b', 'feature')
    starting_sha = git!('rev-parse', 'HEAD').strip
    File.write(File.join(project_path, 'one.txt'), "feature one\n")
    git!('add', 'one.txt')
    git!('commit', '-q', '-m', 'Work cycle 1')
    File.write(File.join(project_path, 'two.txt'), "feature two\n")
    git!('add', 'two.txt')
    git!('commit', '-q', '-m', 'Work cycle 2')

    { base_sha: base_sha, starting_sha: starting_sha }
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
    db[:reviews].insert(
      created_at: Time.now,
      completed_at: nil,
      project_path: File.realpath(project_path),
      number: 1,
      source: 'local',
      branch_name: 'feature',
      starting_commit_sha: starting_sha,
      original_base_ref: 'origin/main',
      original_base_commit_sha: base_sha,
      active_base_ref: 'origin/main',
      active_base_commit_sha: base_sha,
      state: 'reviewer_review',
      final_commit_sha: nil
    )
  end

  def insert_completed_implementation
    db[:work_cycles].insert(
      created_at: Time.now,
      completed_at: Time.now,
      review_id: review_id,
      role: 'worker',
      action: 'implementation',
      provider: nil,
      model: nil,
      reasoning_level: nil
    )
  end

  def review
    db[:reviews].where(id: review_id).first
  end

  def continue_rebase(target_sha)
    ContinueReviewRebase.call(
      project_path: project_path,
      branch_name: 'feature',
      target_base_ref: 'origin/main',
      target_base_commit_sha: target_sha
    )
  end

  def conflict_control(target_sha)
    "RebaseConflict #{review_id}\n" \
      "RebaseTargetRef origin/main\n" \
      "RebaseTargetCommit #{target_sha}"
  end

  def unmerged_paths
    git!('diff', '--name-only', '--diff-filter=U').lines(chomp: true)
  end

  def rebase_in_progress?
    Dir.exist?(File.join(git_directory, 'rebase-merge'))
  end

  def rebase_onto_sha
    File.read(File.join(git_directory, 'rebase-merge', 'onto')).strip
  end

  def git_directory
    git!('rev-parse', '--absolute-git-dir').strip
  end

  def remote_sha(branch_name)
    git_without_path!('--git-dir', origin_path, 'rev-parse', "refs/heads/#{branch_name}").strip
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
