# frozen_string_literal: true

require 'fileutils'
require 'open3'
require 'tmpdir'
require_relative 'spec_helper'

RSpec.describe PrepareReviewRebase do
  let(:db) { Database.connection }
  let(:root_path) { Dir.mktmpdir('autofix-prepare-rebase-spec') }
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
    insert_work_cycle(completed_at: Time.now)
  end

  after do
    FileUtils.remove_entry(root_path)
  end

  it 'prepares an advanced version of the stored active base ref without persisting changes' do
    target_sha = advance_main
    review_before = review

    result = described_class.call(project_path: project_path, branch_name: 'feature')

    expect(result).to eq(
      review_id: review_id,
      review_number: 1,
      project_path: File.realpath(project_path),
      branch_name: 'feature',
      starting_commit_sha: starting_sha,
      original_base_ref: 'origin/main',
      original_base_commit_sha: base_sha,
      active_base_ref: 'origin/main',
      active_base_commit_sha: base_sha,
      target_base_ref: 'origin/main',
      target_base_commit_sha: target_sha,
      head_commit_sha: head_sha,
      commits_after_starting_count: 1
    )
    expect(review).to eq(review_before)
  end

  it 'preserves an explicit ref exactly and resolves it once' do
    target_sha = create_remote_branch('release')

    result = described_class.call(
      project_path: project_path,
      branch_name: 'feature',
      base_ref: 'origin/release'
    )

    expect(result).to include(
      target_base_ref: 'origin/release',
      target_base_commit_sha: target_sha
    )
  end

  it 'rejects a Review without a starting commit' do
    db[:reviews].where(id: review_id).update(starting_commit_sha: nil)

    expect { prepare }.to raise_error('Review 1 has no starting commit')
  end

  it 'rejects a Review without a completed Worker implementation Work Cycle' do
    db[:work_cycles].where(review_id: review_id).delete
    insert_work_cycle(completed_at: Time.now, role: 'reviewer', action: 'review')

    expect { prepare }.
      to raise_error('Review 1 has no completed Worker implementation Work Cycle')
  end

  it 'rejects a Review with an incomplete Work Cycle' do
    incomplete_id = insert_work_cycle(completed_at: nil, role: 'reviewer', action: 'review')

    expect { prepare }.to raise_error("Review 1 has incomplete Work Cycle #{incomplete_id}")
  end

  it 'rejects a checkout on a different branch' do
    git!(project_path, 'checkout', '-q', 'main')

    expect { prepare }.
      to raise_error('Current branch main does not match Review 1 branch feature')
  end

  it 'checks for a dirty tree before fetching' do
    local_base_sha = git!(project_path, 'rev-parse', 'origin/main').strip
    advance_main
    File.write(File.join(project_path, 'untracked.txt'), "dirty\n")

    expect { prepare }.to raise_error(/Working tree is not clean/)
    expect(git!(project_path, 'rev-parse', 'origin/main').strip).to eq(local_base_sha)
  end

  it 'rejects a target ref that does not resolve to a commit' do
    expect do
      described_class.call(
        project_path: project_path,
        branch_name: 'feature',
        base_ref: 'origin/missing'
      )
    end.to raise_error(%r{git .* rev-parse origin/missing\^\{commit\} failed})
  end

  it 'rejects a stored starting commit outside current HEAD history' do
    unrelated_sha = create_remote_branch('unrelated')
    db[:reviews].where(id: review_id).update(starting_commit_sha: unrelated_sha)

    expect { prepare }.
      to raise_error(/git .* merge-base --is-ancestor #{unrelated_sha} #{head_sha} failed/)
  end

  it 'rejects a stored active base outside current HEAD history' do
    unrelated_sha = create_remote_branch('unrelated')
    db[:reviews].where(id: review_id).update(active_base_commit_sha: unrelated_sha)

    expect { prepare }.
      to raise_error(/git .* merge-base --is-ancestor #{unrelated_sha} #{head_sha} failed/)
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

  def head_sha
    repository_shas.fetch(:head_sha)
  end

  def setup_repository
    git_without_path!('init', '--bare', '-q', '--initial-branch=main', origin_path)
    git_without_path!('init', '-q', '--initial-branch=main', project_path)
    configure_git(project_path)
    File.write(File.join(project_path, 'tracked.txt'), "base\n")
    git!(project_path, 'add', 'tracked.txt')
    git!(project_path, 'commit', '-q', '-m', 'Base')
    base_sha = git!(project_path, 'rev-parse', 'HEAD').strip
    git!(project_path, 'remote', 'add', 'origin', origin_path)
    git!(project_path, 'push', '-q', '-u', 'origin', 'main')
    git!(project_path, 'checkout', '-q', '-b', 'feature')
    starting_sha = git!(project_path, 'rev-parse', 'HEAD').strip
    File.write(File.join(project_path, 'tracked.txt'), "feature\n")
    git!(project_path, 'add', 'tracked.txt')
    git!(project_path, 'commit', '-q', '-m', 'Work cycle 1')
    head_sha = git!(project_path, 'rev-parse', 'HEAD').strip

    { base_sha: base_sha, starting_sha: starting_sha, head_sha: head_sha }
  end

  def advance_main
    prepare_updater
    File.write(File.join(updater_path, 'base.txt'), "advanced\n")
    git!(updater_path, 'add', 'base.txt')
    git!(updater_path, 'commit', '-q', '-m', 'Advance main')
    git!(updater_path, 'push', '-q', 'origin', 'main')
    git!(updater_path, 'rev-parse', 'HEAD').strip
  end

  def create_remote_branch(branch_name)
    prepare_updater
    git!(updater_path, 'checkout', '-q', '--orphan', branch_name)
    FileUtils.rm_f(Dir.glob(File.join(updater_path, '*')))
    File.write(File.join(updater_path, "#{branch_name}.txt"), "#{branch_name}\n")
    git!(updater_path, 'add', '-A')
    git!(updater_path, 'commit', '-q', '-m', "Create #{branch_name}")
    git!(updater_path, 'push', '-q', 'origin', branch_name)
    git!(updater_path, 'rev-parse', 'HEAD').strip
  end

  def prepare_updater
    return if Dir.exist?(updater_path)

    git_without_path!('clone', '-q', origin_path, updater_path)
    configure_git(updater_path)
  end

  def configure_git(path)
    git!(path, 'config', 'user.email', 'autofix@example.com')
    git!(path, 'config', 'user.name', 'Autofix')
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
      state: 'reviewer_review'
    )
  end

  def insert_work_cycle(completed_at:, role: 'worker', action: 'implementation')
    db[:work_cycles].insert(
      created_at: Time.now,
      completed_at: completed_at,
      review_id: review_id,
      role: role,
      action: action,
      provider: nil,
      model: nil,
      reasoning_level: nil
    )
  end

  def review
    db[:reviews].where(id: review_id).first
  end

  def prepare
    described_class.call(project_path: project_path, branch_name: 'feature')
  end

  def git!(path, *arguments)
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
