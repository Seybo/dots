# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'open3'
require 'tmpdir'
require_relative 'spec_helper'

RSpec.describe ResumeReview do
  let(:db) { Database.connection }
  let(:project_path) { Dir.mktmpdir('autofix-resume-spec') }

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

  it 'reports when the branch has no incomplete Review' do
    expect(described_class.call(project_path: project_path, branch_name: 'feature')).
      to eq('No incomplete Review.')
  end

  it 'displays the next unresolved issue in Manager selection' do
    review_id = store_review(['Pending issue.'])
    issue_id = review_issue_ids(review_id).first

    expect(described_class.call(project_path: project_path, branch_name: 'feature')).
      to eq("Issue: #{issue_id}\n\n> Pending issue.")
  end

  it 'creates and exposes a missing implementation Work Cycle for a classified Review' do
    review_id = store_review(['Approved issue.', 'Skipped issue.'])
    issue_ids = review_issue_ids(review_id)
    db[:reported_issues].where(id: issue_ids.first).update(decision: 'approved')
    db[:reported_issues].where(id: issue_ids.last).update(decision: 'skipped')

    output = described_class.call(project_path: project_path, branch_name: 'feature')
    work_cycle = db[:work_cycles].first

    expect(output).to eq("AutoFixCycle #{work_cycle.fetch(:id)}\nAutoFixRole worker")
    expect(work_cycle).to include(review_id: review_id, role: 'worker', action: 'implementation')
  end

  it 'waits for an existing incomplete implementation Work Cycle without redispatching it' do
    review_id = store_review(['Approved issue.'])
    issue_id = review_issue_ids(review_id).first
    db[:reported_issues].where(id: issue_id).update(decision: 'approved')
    work_cycle_id = StartImplementationWorkCycle.call(review_id: review_id)

    output = described_class.call(project_path: project_path, branch_name: 'feature')

    expect(output).to eq("WaitWorkCycle #{work_cycle_id}")
    expect(db[:work_cycles].count).to eq(1)
  end

  it 'creates and exposes a missing Reviewer review Work Cycle' do
    review_id, implementation_work_cycle_id = complete_implementation(review_state: 'reviewer_review')

    output = described_class.call(project_path: project_path, branch_name: 'feature')
    review_work_cycle = db[:work_cycles].order(:id).last

    expect(output).to eq("AutoFixCycle #{review_work_cycle.fetch(:id)}\nAutoFixRole reviewer")
    expect(review_work_cycle).to include(
      review_id: review_id,
      previous_work_cycle_id: implementation_work_cycle_id,
      role: 'reviewer',
      action: 'review'
    )
  end

  it 'waits for an existing incomplete Reviewer review Work Cycle without redispatching it' do
    _review_id, implementation_work_cycle_id = complete_implementation(review_state: 'reviewer_review')
    review_work_cycle_id = StartReviewerReviewWorkCycle.call(
      previous_work_cycle_id: implementation_work_cycle_id
    )

    output = described_class.call(project_path: project_path, branch_name: 'feature')

    expect(output).to eq("WaitWorkCycle #{review_work_cycle_id}")
    expect(db[:work_cycles].count).to eq(2)
  end

  it 'does not bypass completed Reviewer findings' do
    _review_id, reviewer_work_cycle_id = complete_reviewer_review(findings: ['Reviewer finding.'])

    output = described_class.call(project_path: project_path, branch_name: 'feature')

    expect(output).to eq(
      "Reviewer review completed (Cycle #{reviewer_work_cycle_id}). Findings:\n- Reviewer finding."
    )
    expect(db[:work_cycles].count).to eq(2)
  end

  it 'creates and exposes the final Worker review Work Cycle after Reviewer passes' do
    review_id, reviewer_work_cycle_id = complete_reviewer_review(findings: [])

    output = described_class.call(project_path: project_path, branch_name: 'feature')
    review_work_cycle = db[:work_cycles].order(:id).last

    expect(output).to eq("AutoFixCycle #{review_work_cycle.fetch(:id)}\nAutoFixRole worker")
    expect(review_work_cycle).to include(
      review_id: review_id,
      previous_work_cycle_id: reviewer_work_cycle_id,
      role: 'worker',
      action: 'review'
    )
  end

  it 'waits for an existing incomplete final Worker review Work Cycle without redispatching it' do
    _review_id, reviewer_work_cycle_id = complete_reviewer_review(findings: [])
    review_work_cycle_id = StartWorkerReviewWorkCycle.call(
      previous_work_cycle_id: reviewer_work_cycle_id
    )

    output = described_class.call(project_path: project_path, branch_name: 'feature')

    expect(output).to eq("WaitWorkCycle #{review_work_cycle_id}")
    expect(db[:work_cycles].count).to eq(3)
  end

  def complete_implementation(review_state:)
    review_id = store_review(['Approved issue.'])
    issue_id = review_issue_ids(review_id).first
    db[:reported_issues].where(id: issue_id).update(decision: 'approved')
    implementation_work_cycle_id = StartImplementationWorkCycle.call(review_id: review_id)
    db[:work_cycles].where(id: implementation_work_cycle_id).update(
      completed_at: Time.now,
      result: '{"status":"completed"}',
      commit_sha: git!('rev-parse', 'HEAD').strip
    )
    db[:reviews].where(id: review_id).update(state: review_state)

    [review_id, implementation_work_cycle_id]
  end

  def complete_reviewer_review(findings:)
    review_id, implementation_work_cycle_id = complete_implementation(review_state: 'reviewer_review')
    reviewer_work_cycle_id = StartReviewerReviewWorkCycle.call(
      previous_work_cycle_id: implementation_work_cycle_id
    )
    db[:work_cycles].where(id: reviewer_work_cycle_id).update(
      completed_at: Time.now,
      result: JSON.generate('findings' => findings)
    )
    next_state = findings.empty? ? 'worker_review' : 'reviewer_review'
    db[:reviews].where(id: review_id).update(state: next_state)

    [review_id, reviewer_work_cycle_id]
  end

  def store_review(issue_bodies)
    StoreReview.call(
      project_path: project_path,
      source: 'local',
      branch_name: 'feature',
      base_ref: 'origin/main',
      base_commit_sha: 'base-sha',
      issue_data: issue_bodies.map { |body| { source_id: nil, body: body } }
    )
  end

  def review_issue_ids(review_id)
    db[:review_issues].where(review_id: review_id).order(:id).select_map(:reported_issue_id)
  end

  def git!(*arguments)
    stdout, stderr, status = Open3.capture3('git', '-C', project_path, *arguments)
    raise stderr unless status.success?

    stdout
  end
end
