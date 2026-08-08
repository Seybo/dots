# frozen_string_literal: true

require 'json'
require_relative '../../spec/spec_helper'

RSpec.describe 'ShowTaskWorkCycle' do
  let(:service_class) { Object.const_get(:ShowTaskWorkCycle) }
  let(:db) { Database.connection }
  let(:task_id) do
    db[:tasks].insert(
      created_at: Time.now,
      task_path: '/tasks/0028-task',
      project_path: '/project',
      branch_name: 'feature',
      starting_commit_sha: 'starting-sha',
      state: 'initialized'
    )
  end

  before do
    allow(Database).to receive(:readonly_connection).and_return(db)
  end

  it 'returns initial Worker context with no completed step commits or Reported Issues' do
    work_cycle_id = db[:work_cycles].insert(
      created_at: Time.now,
      task_id: task_id,
      step_number: 2,
      role: 'worker',
      action: 'implementation'
    )

    context = JSON.parse(service_class.call(work_cycle_id: work_cycle_id))

    expect(context).to eq(
      'work_cycle_id' => work_cycle_id,
      'task_id' => task_id,
      'role' => 'worker',
      'action' => 'implementation',
      'task_path' => '/tasks/0028-task',
      'project_path' => '/project',
      'branch_name' => 'feature',
      'starting_commit_sha' => 'starting-sha',
      'super_review_agent' => 'claude',
      'scope' => 'step_implementation',
      'step_number' => 2,
      'step_commit_count' => 0,
      'inputs' => [],
      'reported_issues' => []
    )
  end

  it 'returns Reviewer context with its derived step, cumulative commit count, and ordered issues' do
    2.times do
      db[:work_cycles].insert(
        created_at: Time.now,
        completed_at: Time.now,
        task_id: task_id,
        step_number: 2,
        role: 'worker',
        action: 'implementation'
      )
    end
    implementation_id = db[:work_cycles].order(:id).last.fetch(:id)
    input_issue_id = insert_issue(body: 'Approved correction.', decision: 'approved')
    db[:work_cycle_inputs].insert(
      created_at: Time.now,
      work_cycle_id: implementation_id,
      reported_issue_id: input_issue_id
    )
    reviewer_work_cycle_id = db[:work_cycles].insert(
      created_at: Time.now,
      task_id: task_id,
      role: 'reviewer',
      action: 'review'
    )
    db[:work_cycle_inputs].insert(
      created_at: Time.now,
      work_cycle_id: reviewer_work_cycle_id,
      reported_issue_id: input_issue_id
    )
    reported_issue_id = insert_issue(body: 'New review concern.', decision: nil)
    db[:work_cycle_reported_issues].insert(
      created_at: Time.now,
      work_cycle_id: reviewer_work_cycle_id,
      reported_issue_id: reported_issue_id
    )

    context = JSON.parse(service_class.call(work_cycle_id: reviewer_work_cycle_id))

    expect(context).to include(
      'work_cycle_id' => reviewer_work_cycle_id,
      'role' => 'reviewer',
      'action' => 'review',
      'starting_commit_sha' => 'starting-sha',
      'super_review_agent' => 'claude',
      'scope' => 'step_review',
      'step_number' => 2,
      'step_commit_count' => 2
    )
    expect(context.fetch('inputs')).to eq(
      [
        {
          'id' => input_issue_id,
          'source' => 'reviewer',
          'body' => 'Approved correction.',
          'decision' => 'approved'
        },
      ]
    )
    expect(context.fetch('reported_issues')).to eq(
      [
        {
          'id' => reported_issue_id,
          'source' => 'reviewer',
          'body' => 'New review concern.',
          'decision' => nil
        },
      ]
    )
  end

  it 'returns the persisted whole-task super-review context' do
    db[:tasks].where(id: task_id).update(state: 'super_review', super_review_agent: 'codex')
    db[:work_cycles].insert(
      created_at: Time.now,
      completed_at: Time.now,
      task_id: task_id,
      step_number: 2,
      role: 'worker',
      action: 'implementation'
    )
    reviewer_work_cycle_id = db[:work_cycles].insert(
      created_at: Time.now,
      task_id: task_id,
      role: 'reviewer',
      action: 'review'
    )

    context = JSON.parse(service_class.call(work_cycle_id: reviewer_work_cycle_id))

    expect(context).to include(
      'starting_commit_sha' => 'starting-sha',
      'super_review_agent' => 'codex',
      'scope' => 'super_review',
      'step_number' => nil,
      'step_commit_count' => nil,
      'inputs' => []
    )
  end

  it 'returns the whole-task final Worker self-review context' do
    db[:tasks].where(id: task_id).update(state: 'worker_final_review')
    db[:work_cycles].insert(
      created_at: Time.now,
      completed_at: Time.now,
      task_id: task_id,
      step_number: 2,
      role: 'worker',
      action: 'implementation'
    )
    worker_review_id = db[:work_cycles].insert(
      created_at: Time.now,
      task_id: task_id,
      role: 'worker',
      action: 'review'
    )

    context = JSON.parse(service_class.call(work_cycle_id: worker_review_id))

    expect(context).to include(
      'starting_commit_sha' => 'starting-sha',
      'scope' => 'final_worker_review',
      'step_number' => nil,
      'step_commit_count' => nil,
      'inputs' => []
    )
  end

  it 'returns nil-step whole-task correction and exact scoped-review context' do
    db[:tasks].where(id: task_id).update(state: 'super_review')
    input_issue_id = insert_issue(body: 'Approved whole-task correction.', decision: 'approved')
    correction_id = db[:work_cycles].insert(
      created_at: Time.now,
      completed_at: Time.now,
      task_id: task_id,
      step_number: nil,
      role: 'worker',
      action: 'implementation'
    )
    db[:work_cycle_inputs].insert(
      created_at: Time.now,
      work_cycle_id: correction_id,
      reported_issue_id: input_issue_id
    )

    correction_context = JSON.parse(service_class.call(work_cycle_id: correction_id))

    expect(correction_context).to include(
      'starting_commit_sha' => 'starting-sha',
      'scope' => 'whole_task_correction',
      'step_number' => nil,
      'step_commit_count' => nil
    )

    reviewer_work_cycle_id = db[:work_cycles].insert(
      created_at: Time.now,
      task_id: task_id,
      role: 'reviewer',
      action: 'review'
    )
    db[:work_cycle_inputs].insert(
      created_at: Time.now,
      work_cycle_id: reviewer_work_cycle_id,
      reported_issue_id: input_issue_id
    )

    review_context = JSON.parse(service_class.call(work_cycle_id: reviewer_work_cycle_id))

    expect(review_context).to include(
      'starting_commit_sha' => 'starting-sha',
      'scope' => 'whole_task_correction_review',
      'step_number' => nil,
      'step_commit_count' => 1
    )
    expect(review_context.fetch('inputs').map { |issue| issue.fetch('id') }).to eq([input_issue_id])
  end

  def insert_issue(body:, decision:)
    issue_id = StoreIssue.call(project_path: '/project', source: 'reviewer', body: body)
    db[:reported_issues].where(id: issue_id).update(decision: decision)
    issue_id
  end
end
