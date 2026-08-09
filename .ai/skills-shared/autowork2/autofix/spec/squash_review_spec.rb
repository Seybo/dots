# frozen_string_literal: true

require 'fileutils'
require 'open3'
require 'tmpdir'
require_relative '../../spec/spec_helper'

RSpec.describe SquashReview do
  let(:db) { Database.connection }
  let(:project_path) { Dir.mktmpdir('autofix-squash-review-spec') }

  before do
    git!('init', '-q')
    git!('config', 'user.email', 'autofix@example.com')
    git!('config', 'user.name', 'Autofix')
    File.write(File.join(project_path, 'tracked.txt'), "initial\n")
    git!('add', 'tracked.txt')
    git!('commit', '-q', '-m', 'Initial commit')
  end

  after do
    FileUtils.remove_entry(project_path)
  end

  it 'squashes a completed Review without changing its persisted state' do
    review_id, work_cycle_id, starting_commit_sha = create_completed_review
    review_before_squash = review(review_id)

    output = described_class.call(review_id: review_id, project_path: project_path)
    final_commit_sha = git!('rev-parse', 'HEAD').strip

    expect(output).to eq(
      "Review 1 squashed locally.\n" \
      "Final commit: #{final_commit_sha} Review 1\n" \
      'Push: not performed.'
    )
    expect(git!('log', '-1', '--format=%s').strip).to eq('Review 1')
    expect(git!('rev-parse', 'HEAD^').strip).to eq(starting_commit_sha)
    expect(git!('status', '--porcelain')).to eq('')
    expect(review(review_id)).to eq(review_before_squash)
    expect(db[:work_cycles].where(id: work_cycle_id).get(:completed_at)).not_to be_nil
  end

  it 'refuses an incomplete Review without changing Git or state' do
    review_id, _work_cycle_id, _starting_commit_sha = create_completed_review
    db[:reviews].where(id: review_id).update(state: 'manager_finalizing', completed_at: nil)
    review_before_squash = review(review_id)
    head_before_squash = git!('rev-parse', 'HEAD').strip

    expect do
      described_class.call(review_id: review_id, project_path: project_path)
    end.to raise_error('Review 1 is not completed')

    expect(review(review_id)).to eq(review_before_squash)
    expect(git!('rev-parse', 'HEAD').strip).to eq(head_before_squash)
  end

  it 'refuses a dirty tree without changing completed state' do
    review_id, _work_cycle_id, _starting_commit_sha = create_completed_review
    review_before_squash = review(review_id)
    head_before_squash = git!('rev-parse', 'HEAD').strip
    File.write(File.join(project_path, 'tracked.txt'), "dirty\n")

    expect do
      described_class.call(review_id: review_id, project_path: project_path)
    end.to raise_error(RuntimeError, /Working tree is not clean/)

    expect(review(review_id)).to eq(review_before_squash)
    expect(git!('rev-parse', 'HEAD').strip).to eq(head_before_squash)
  end

  it 'refuses unexpected commits without changing completed state' do
    review_id, _work_cycle_id, _starting_commit_sha = create_completed_review
    File.write(File.join(project_path, 'unexpected.txt'), "unexpected\n")
    git!('add', 'unexpected.txt')
    git!('commit', '-q', '-m', 'Unexpected commit')
    review_before_squash = review(review_id)
    head_before_squash = git!('rev-parse', 'HEAD').strip

    expect do
      described_class.call(review_id: review_id, project_path: project_path)
    end.to raise_error(RuntimeError, /commit sequence does not match/)

    expect(review(review_id)).to eq(review_before_squash)
    expect(git!('rev-parse', 'HEAD').strip).to eq(head_before_squash)
  end

  private

  def create_completed_review
    review_id = ReviewFactory.call(
      project_path: project_path,
      source: 'local',
      branch_name: git!('branch', '--show-current').strip,
      base_ref: 'origin/main',
      base_commit_sha: 'base-sha',
      issue_data: [{ source_id: nil, body: 'Approved issue.' }]
    )
    issue_id = db[:review_issues].where(review_id: review_id).get(:reported_issue_id)
    db[:reported_issues].where(id: issue_id).update(decision: 'approved')
    work_cycle_id = StartImplementationWorkCycle.call(review_id: review_id)
    starting_commit_sha = review(review_id).fetch(:starting_commit_sha)
    File.write(File.join(project_path, 'tracked.txt'), "implemented\n")
    git!('add', 'tracked.txt')
    git!('commit', '-q', '-m', "Work cycle #{work_cycle_id}")
    db[:work_cycles].where(id: work_cycle_id).update(completed_at: Time.now)
    db[:reviews].where(id: review_id).update(state: 'completed', completed_at: Time.now)

    [review_id, work_cycle_id, starting_commit_sha]
  end

  def review(review_id)
    db[:reviews].where(id: review_id).first
  end

  def git!(*arguments)
    stdout, stderr, status = Open3.capture3('git', '-C', project_path, *arguments)
    raise stderr unless status.success?

    stdout
  end
end
