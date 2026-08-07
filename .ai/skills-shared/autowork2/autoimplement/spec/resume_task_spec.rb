# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'
require_relative '../../spec/spec_helper'

RSpec.describe 'ResumeTask' do
  let(:service_class) { Object.const_get(:ResumeTask) }
  let(:db) { Database.connection }
  let(:task_path) { Dir.mktmpdir('resume-task-spec') }
  let(:task_id) do
    db[:tasks].insert(
      created_at: Time.now,
      task_path: task_path,
      project_path: '/project',
      branch_name: 'feature',
      starting_commit_sha: 'starting-sha',
      state: 'initialized'
    )
  end

  before do
    File.write(
      File.join(task_path, 'steps.md'),
      "# Steps\n\n## Step 1: First\n\n## Step 2: Second\n"
    )
    allow(ValidateCleanGitState).to receive(:call).and_return('head-sha')
  end

  after do
    FileUtils.remove_entry(task_path)
  end

  it 'creates and renders one new Worker implementation handoff' do
    output = service_class.call(task_id: task_id)
    work_cycle = db[:work_cycles].first

    expect(output).to eq("AutoImplementCycle #{work_cycle.fetch(:id)}")
    expect(work_cycle).to include(
      task_id: task_id,
      step_number: 1,
      role: 'worker',
      action: 'implementation',
      completed_at: nil
    )
  end

  it 'waits for any incomplete Work Cycle without redispatch or a clean-Git check' do
    implementation_id = insert_implementation
    db[:work_cycles].where(id: implementation_id).update(completed_at: Time.now)
    reviewer_work_cycle_id = insert_review
    allow(ValidateCleanGitState).to receive(:call).and_raise('should not run')

    expect(service_class.call(task_id: task_id)).to eq("WaitWorkCycle #{reviewer_work_cycle_id}")
    expect(db[:work_cycles].count).to eq(2)
  end

  it 'starts Reviewer review after a completed implementation' do
    implementation_id = insert_implementation
    db[:work_cycles].where(id: implementation_id).update(completed_at: Time.now)

    output = service_class.call(task_id: task_id)
    reviewer_work_cycle = db[:work_cycles].order(:id).last

    expect(output).to eq("AutoImplementCycle #{reviewer_work_cycle.fetch(:id)}")
    expect(reviewer_work_cycle).to include(
      task_id: task_id,
      step_number: nil,
      role: 'reviewer',
      action: 'review',
      completed_at: nil
    )
  end

  it 'starts a fresh Reviewer review after a completed correction' do
    insert_implementation(completed_at: Time.now)
    review_work_cycle_id = insert_review(completed_at: Time.now)
    issue_id = insert_produced_issue(review_work_cycle_id, decision: 'approved')
    correction_id = insert_implementation(completed_at: Time.now)
    db[:work_cycle_inputs].insert(
      created_at: Time.now,
      work_cycle_id: correction_id,
      reported_issue_id: issue_id
    )

    output = service_class.call(task_id: task_id)
    reviewer_work_cycle = db[:work_cycles].order(:id).last

    expect(output).to eq("AutoImplementCycle #{reviewer_work_cycle.fetch(:id)}")
    expect(reviewer_work_cycle).to include(role: 'reviewer', action: 'review')
    expect(db[:work_cycle_inputs].where(work_cycle_id: reviewer_work_cycle.fetch(:id)).
      select_map(:reported_issue_id)).to eq([issue_id])
  end

  it 'renders the oldest undecided issue from the latest Reviewer pass' do
    insert_implementation(completed_at: Time.now)
    review_work_cycle_id = insert_review(completed_at: Time.now)
    first_issue_id = insert_produced_issue(review_work_cycle_id)
    insert_produced_issue(review_work_cycle_id, body: 'Second issue.')

    output = service_class.call(task_id: task_id)

    expect(output).to eq("Issue: #{first_issue_id}\n\n> Review issue.")
    expect(db[:work_cycles].count).to eq(2)
  end

  it 'accepts a clean or skipped-only Reviewer pass without starting the next step' do
    insert_implementation(completed_at: Time.now)
    clean_review_id = insert_review(completed_at: Time.now)

    expect(service_class.call(task_id: task_id)).to eq('Step 1 accepted.')

    db[:work_cycles].where(id: clean_review_id).delete
    skipped_review_id = insert_review(completed_at: Time.now)
    insert_produced_issue(skipped_review_id, decision: 'skipped')

    expect(service_class.call(task_id: task_id)).to eq('Step 1 accepted.')
    expect(db[:work_cycles].where(role: 'worker', action: 'implementation').count).to eq(1)
  end

  it 'creates one correction with every approved issue after the pass is settled' do
    insert_implementation(completed_at: Time.now)
    review_work_cycle_id = insert_review(completed_at: Time.now)
    approved_issue_ids = [
      insert_produced_issue(review_work_cycle_id, body: 'First fix.', decision: 'approved'),
      insert_produced_issue(review_work_cycle_id, body: 'Second fix.', decision: 'approved'),
    ]
    insert_produced_issue(review_work_cycle_id, body: 'Skipped issue.', decision: 'skipped')

    output = service_class.call(task_id: task_id)
    correction = db[:work_cycles].order(:id).last

    expect(output).to eq("AutoImplementCycle #{correction.fetch(:id)}")
    expect(correction).to include(step_number: 1, role: 'worker', action: 'implementation')
    expect(db[:work_cycle_inputs].where(work_cycle_id: correction.fetch(:id)).order(:id).
      select_map(:reported_issue_id)).to eq(approved_issue_ids)
  end

  def insert_implementation(completed_at: nil)
    db[:work_cycles].insert(
      created_at: Time.now,
      completed_at: completed_at,
      task_id: task_id,
      step_number: 1,
      role: 'worker',
      action: 'implementation'
    )
  end

  def insert_review(completed_at: nil)
    db[:work_cycles].insert(
      created_at: Time.now,
      completed_at: completed_at,
      task_id: task_id,
      role: 'reviewer',
      action: 'review'
    )
  end

  def insert_produced_issue(work_cycle_id, body: 'Review issue.', decision: nil)
    issue_id = StoreIssue.call(project_path: '/project', source: 'reviewer', body: body)
    db[:reported_issues].where(id: issue_id).update(decision: decision)
    db[:work_cycle_reported_issues].insert(
      created_at: Time.now,
      work_cycle_id: work_cycle_id,
      reported_issue_id: issue_id
    )
    issue_id
  end
end
