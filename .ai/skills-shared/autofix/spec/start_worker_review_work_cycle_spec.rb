# frozen_string_literal: true

require 'fileutils'
require 'open3'
require 'tmpdir'
require_relative 'spec_helper'

RSpec.describe StartWorkerReviewWorkCycle do
  let(:db) { Database.connection }
  let(:project_path) { Dir.mktmpdir('autofix-worker-review-spec') }

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

  it 'creates one final Worker review Work Cycle with the latest implementation inputs' do
    review_id, _reviewer_work_cycle_id, issue_ids = complete_reviewer_pass

    review_work_cycle_id = described_class.call(review_id: review_id)

    expect(db[:work_cycles].where(id: review_work_cycle_id).first).to include(
      review_id: review_id,
      role: 'worker',
      action: 'review',
      completed_at: nil
    )
    expect(db[:work_cycle_inputs].where(work_cycle_id: review_work_cycle_id).order(:id).
      select_map(:reported_issue_id)).to eq(issue_ids)
    expect(db[:reviews].where(id: review_id).get(:state)).to eq('worker_review')
  end

  it 'creates nothing when the working tree is dirty' do
    review_id, _reviewer_work_cycle_id, = complete_reviewer_pass
    File.write(File.join(project_path, 'tracked.txt'), "changed\n")

    expect { described_class.call(review_id: review_id) }.
      to raise_error(RuntimeError, /Working tree is not clean/)

    expect(db[:work_cycles].count).to eq(2)
    expect(db[:work_cycle_inputs].count).to eq(4)
  end

  it 'does not create a second Worker review for the Review' do
    review_id, _reviewer_work_cycle_id, = complete_reviewer_pass
    described_class.call(review_id: review_id)

    expect { described_class.call(review_id: review_id) }.
      to raise_error(RuntimeError, "Review #{review_id} already has a Worker review Work Cycle")

    expect(db[:work_cycles].count).to eq(3)
  end

  def complete_reviewer_pass
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
      completed_at: Time.now
    )
    db[:reviews].where(id: review_id).update(state: 'reviewer_review')
    reviewer_work_cycle_id = StartReviewerReviewWorkCycle.call(review_id: review_id)
    db[:work_cycles].where(id: reviewer_work_cycle_id).update(
      completed_at: Time.now
    )
    db[:reviews].where(id: review_id).update(state: 'worker_review')

    [review_id, reviewer_work_cycle_id, issue_ids]
  end

  def git!(*arguments)
    stdout, stderr, status = Open3.capture3('git', '-C', project_path, *arguments)
    raise stderr unless status.success?

    stdout
  end
end
