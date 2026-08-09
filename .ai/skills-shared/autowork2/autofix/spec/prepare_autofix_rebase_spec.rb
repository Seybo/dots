# frozen_string_literal: true

require 'fileutils'
require 'open3'
require 'tmpdir'
require_relative '../../spec/spec_helper'

RSpec.describe PrepareAutofixRebase do
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
    db[:tasks].update(starting_commit_sha: base_sha)
  end

  after do
    FileUtils.remove_entry(root_path)
  end

  it 'prepares Task and Review boundaries without requiring a completed implementation' do
    target_sha = advance_main
    task = db[:tasks].first

    result = prepare

    expect(result).to include(
      task_id: task.fetch(:id),
      task_path: task.fetch(:task_path),
      review_id: review_id,
      review_number: 1,
      project_path: File.realpath(project_path),
      branch_name: 'feature',
      task_starting_commit_sha: base_sha,
      review_starting_commit_sha: review_starting_sha,
      active_base_ref: 'origin/main',
      active_base_commit_sha: base_sha,
      target_base_ref: 'origin/main',
      target_base_commit_sha: target_sha
    )
    expect(result.fetch(:git_preparation).fetch(:boundary_counts)).to eq(task: 2, review: 1)
  end

  it 'prepares a completed Task before a Review exists' do
    db[:reviews].where(id: review_id).delete

    result = prepare

    expect(result).to include(review_id: nil, review_number: nil)
    expect(result.fetch(:git_preparation).fetch(:boundary_counts)).to eq(task: 2)
  end

  it 'preserves an explicit ref exactly' do
    target_sha = create_remote_branch('release')

    result = described_class.call(
      task_path: task_path,
      project_path: project_path,
      base_ref: 'origin/release'
    )

    expect(result).to include(
      target_base_ref: 'origin/release',
      target_base_commit_sha: target_sha
    )
  end

  it 'rejects an incomplete Autofix Work Cycle without requiring a prior implementation' do
    work_cycle_id = db[:work_cycles].insert(
      created_at: Time.now,
      completed_at: nil,
      review_id: review_id,
      role: 'reviewer',
      action: 'review',
      provider: nil,
      model: nil,
      reasoning_level: nil
    )

    expect { prepare }.
      to raise_error("Review 1 has incomplete Work Cycle #{work_cycle_id}")
  end

  it 'rejects a Task that is no longer durably completed' do
    db[:tasks].update(state: 'initialized')

    expect { prepare }.to raise_error(/Task \d+ cannot Autofix rebase from state initialized/)
  end

  it 'rejects local-provider Task configuration' do
    task = db[:tasks].first
    config = ReadTaskConfig.call(task_path: task.fetch(:task_path))
    config.fetch('branch').merge!(
      'name' => 'main',
      'original_base_ref' => base_sha,
      'active_base_ref' => base_sha
    )
    File.write(File.join(task.fetch(:task_path), 'config.json'), JSON.generate(config))
    git!(project_path, 'checkout', '-q', 'main')

    expect { prepare }.to raise_error('Local Tasks cannot be rebased')
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
        task_path: task_path,
        project_path: project_path,
        base_ref: 'origin/missing'
      )
    end.to raise_error(%r{git .* rev-parse origin/missing\^\{commit\} failed})
  end

  it 'rejects either stored starting boundary outside current HEAD history' do
    unrelated_sha = create_remote_branch('unrelated')

    db[:tasks].update(starting_commit_sha: unrelated_sha)
    expect { prepare }.
      to raise_error(/git .* merge-base --is-ancestor #{unrelated_sha} .* failed/)

    db[:tasks].update(starting_commit_sha: base_sha)
    db[:reviews].where(id: review_id).update(starting_commit_sha: unrelated_sha)
    expect { prepare }.
      to raise_error(/git .* merge-base --is-ancestor #{unrelated_sha} .* failed/)
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
    File.write(File.join(project_path, 'task.txt'), "implemented\n")
    git!(project_path, 'add', 'task.txt')
    git!(project_path, 'commit', '-q', '-m', 'Autoimplement Task')
    review_starting_sha = git!(project_path, 'rev-parse', 'HEAD').strip
    File.write(File.join(project_path, 'review.txt'), "corrected\n")
    git!(project_path, 'add', 'review.txt')
    git!(project_path, 'commit', '-q', '-m', 'Autofix Review')

    { base_sha: base_sha, review_starting_sha: review_starting_sha }
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
    ReviewFactory.insert(
      project_path: File.realpath(project_path),
      branch_name: 'feature',
      starting_commit_sha: review_starting_sha,
      base_ref: 'origin/main',
      base_commit_sha: base_sha,
      state: 'manager_issues_assessment'
    )
  end

  def task_path
    db[:tasks].first.fetch(:task_path)
  end

  def prepare
    described_class.call(task_path: task_path, project_path: project_path)
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
