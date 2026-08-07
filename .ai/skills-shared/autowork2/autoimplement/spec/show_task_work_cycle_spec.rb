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

  def insert_issue(body:, decision:)
    issue_id = StoreIssue.call(project_path: '/project', source: 'reviewer', body: body)
    db[:reported_issues].where(id: issue_id).update(decision: decision)
    issue_id
  end
end
