# frozen_string_literal: true

require_relative '../../spec/spec_helper'

RSpec.describe StartTaskReviewerReviewWorkCycle do
  let(:db) { Database.connection }
  let(:task_id) do
    db[:tasks].insert(
      created_at: Time.now,
      task_path: '/tasks/28',
      project_path: '/project',
      branch_name: 'feature',
      starting_commit_sha: 'starting-sha',
      state: 'initialized'
    )
  end

  before do
    allow(ValidateCleanGitState).to receive(:call).and_return('head-sha')
  end

  it 'creates a Task-owned Reviewer Work Cycle for the latest completed implementation' do
    first_implementation_id = insert_implementation(step_number: 1)
    db[:work_cycles].where(id: first_implementation_id).update(completed_at: Time.now)
    implementation_id = insert_implementation(step_number: 2)
    db[:work_cycles].where(id: implementation_id).update(completed_at: Time.now)
    issue_id = StoreIssue.call(
      project_path: '/project',
      source: 'reviewer',
      body: 'Approved correction.'
    )
    db[:reported_issues].where(id: issue_id).update(decision: 'approved')
    db[:work_cycle_inputs].insert(
      created_at: Time.now,
      work_cycle_id: implementation_id,
      reported_issue_id: issue_id
    )

    work_cycle_id = described_class.call(task_id: task_id)

    expect(db[:work_cycles].where(id: work_cycle_id).first).to include(
      task_id: task_id,
      review_id: nil,
      step_number: nil,
      role: 'reviewer',
      action: 'review',
      completed_at: nil
    )
    expect(db[:work_cycle_inputs].where(work_cycle_id: work_cycle_id).select_map(:reported_issue_id)).
      to eq([issue_id])
    expect(ValidateCleanGitState).to have_received(:call).with(project_path: '/project')
  end

  it 'creates a scoped Reviewer Work Cycle for a whole-task correction' do
    db[:tasks].where(id: task_id).update(state: 'super_review')
    issue_id = StoreIssue.call(
      project_path: '/project',
      source: 'reviewer',
      body: 'Approved whole-task correction.'
    )
    db[:reported_issues].where(id: issue_id).update(decision: 'approved')
    implementation_id = insert_implementation(step_number: nil)
    db[:work_cycles].where(id: implementation_id).update(completed_at: Time.now)
    db[:work_cycle_inputs].insert(
      created_at: Time.now,
      work_cycle_id: implementation_id,
      reported_issue_id: issue_id
    )

    work_cycle_id = described_class.call(task_id: task_id)

    expect(db[:work_cycles].where(id: work_cycle_id).first).to include(
      task_id: task_id,
      step_number: nil,
      role: 'reviewer',
      action: 'review'
    )
    expect(db[:work_cycle_inputs].where(work_cycle_id: work_cycle_id).
      select_map(:reported_issue_id)).to eq([issue_id])
  end

  it 'creates nothing when Git is dirty' do
    implementation_id = insert_implementation(step_number: 1)
    db[:work_cycles].where(id: implementation_id).update(completed_at: Time.now)
    allow(ValidateCleanGitState).to receive(:call).and_raise('Working tree is not clean')

    expect { described_class.call(task_id: task_id) }.
      to raise_error(RuntimeError, 'Working tree is not clean')

    expect(db[:work_cycles].count).to eq(1)
  end

  it 'fails when the Task has no completed implementation' do
    expect { described_class.call(task_id: task_id) }.
      to raise_error(RuntimeError, "Task #{task_id} has no completed implementation Work Cycle")

    expect(ValidateCleanGitState).not_to have_received(:call)
  end

  def insert_implementation(step_number:)
    db[:work_cycles].insert(
      created_at: Time.now,
      task_id: task_id,
      step_number: step_number,
      role: 'worker',
      action: 'implementation'
    )
  end
end
