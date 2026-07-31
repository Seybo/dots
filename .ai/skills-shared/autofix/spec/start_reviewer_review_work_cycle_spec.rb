# frozen_string_literal: true

require 'fileutils'
require 'open3'
require 'tmpdir'
require_relative 'spec_helper'

RSpec.describe StartReviewerReviewWorkCycle do
  let(:db) { Database.connection }
  let(:project_path) { Dir.mktmpdir('autofix-reviewer-review-spec') }

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

  it 'creates one Reviewer review Work Cycle with the implementation inputs' do
    review_id, implementation_work_cycle_id, issue_ids = complete_implementation

    review_work_cycle_id = described_class.call(previous_work_cycle_id: implementation_work_cycle_id)

    expect(db[:work_cycles].where(id: review_work_cycle_id).first).to include(
      review_id: review_id,
      previous_work_cycle_id: implementation_work_cycle_id,
      role: 'reviewer',
      action: 'review',
      completed_at: nil,
      result: nil,
      commit_sha: nil
    )
    expect(db[:work_cycle_inputs].where(work_cycle_id: review_work_cycle_id).order(:id).
      select_map(:reported_issue_id)).to eq(issue_ids)
    expect(db[:reviews].where(id: review_id).get(:state)).to eq('reviewer_review')
  end

  it 'creates nothing when the working tree is dirty' do
    _review_id, implementation_work_cycle_id, = complete_implementation
    File.write(File.join(project_path, 'tracked.txt'), "changed\n")

    expect { described_class.call(previous_work_cycle_id: implementation_work_cycle_id) }.
      to raise_error(RuntimeError, /Working tree is not clean/)

    expect(db[:work_cycles].count).to eq(1)
    expect(db[:work_cycle_inputs].count).to eq(2)
  end

  def complete_implementation
    review_id = StoreReview.call(
      project_path: project_path,
      source: 'local',
      branch_name: 'feature',
      base_ref: 'origin/main',
      base_commit_sha: 'base-sha',
      issue_data: [
        { source_id: nil, body: 'First approved issue.' },
        { source_id: nil, body: 'Second approved issue.' },
      ]
    )
    issue_ids = db[:review_issues].where(review_id: review_id).order(:id).select_map(:reported_issue_id)
    db[:reported_issues].where(id: issue_ids).update(decision: 'approved')
    implementation_work_cycle_id = StartImplementationWorkCycle.call(review_id: review_id)
    db[:work_cycles].where(id: implementation_work_cycle_id).update(
      completed_at: Time.now,
      result: '{"status":"completed"}',
      commit_sha: git!('rev-parse', 'HEAD').strip
    )
    db[:reviews].where(id: review_id).update(state: 'reviewer_review')

    [review_id, implementation_work_cycle_id, issue_ids]
  end

  def git!(*arguments)
    stdout, stderr, status = Open3.capture3('git', '-C', project_path, *arguments)
    raise stderr unless status.success?

    stdout
  end
end
