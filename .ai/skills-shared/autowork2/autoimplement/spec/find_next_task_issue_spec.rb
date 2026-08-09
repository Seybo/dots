# frozen_string_literal: true

require_relative '../../spec/spec_helper'

RSpec.describe FindNextTaskIssue do
  let(:db) { Database.connection }
  let(:task_id) do
    db[:tasks].insert(
      created_at: Time.now,
      task_path: '/tasks/28',
      project_path: '/project',
      starting_commit_sha: 'starting-sha',
      state: 'initialized'
    )
  end

  it 'selects the oldest undecided issue from the exact Reviewer Work Cycle' do
    older_review_work_cycle_id = insert_review_work_cycle
    insert_produced_issue(
      work_cycle_id: older_review_work_cycle_id,
      body: 'Older pass issue.'
    )
    review_work_cycle_id = insert_review_work_cycle
    decided_issue_id = insert_produced_issue(
      work_cycle_id: review_work_cycle_id,
      body: 'Decided issue.'
    )
    db[:reported_issues].where(id: decided_issue_id).update(decision: 'skipped')
    first_issue_id = insert_produced_issue(
      work_cycle_id: review_work_cycle_id,
      body: 'First undecided issue.'
    )
    insert_produced_issue(
      work_cycle_id: review_work_cycle_id,
      body: 'Second undecided issue.'
    )

    issue = described_class.call(review_work_cycle_id: review_work_cycle_id)

    expect(issue).to include(id: first_issue_id, body: 'First undecided issue.', decision: nil)
  end

  it 'returns nil when the exact Reviewer Work Cycle has no undecided issue' do
    older_review_work_cycle_id = insert_review_work_cycle
    insert_produced_issue(
      work_cycle_id: older_review_work_cycle_id,
      body: 'Older pass issue.'
    )
    review_work_cycle_id = insert_review_work_cycle
    issue_id = insert_produced_issue(work_cycle_id: review_work_cycle_id, body: 'Decided issue.')
    db[:reported_issues].where(id: issue_id).update(decision: 'approved')

    expect(described_class.call(review_work_cycle_id: review_work_cycle_id)).to be_nil
  end

  def insert_review_work_cycle
    db[:work_cycles].insert(
      created_at: Time.now,
      completed_at: Time.now,
      task_id: task_id,
      role: 'reviewer',
      action: 'review'
    )
  end

  def insert_produced_issue(work_cycle_id:, body:)
    issue_id = StoreIssue.call(project_path: '/project', source: 'reviewer', body: body)
    db[:work_cycle_reported_issues].insert(
      created_at: Time.now,
      work_cycle_id: work_cycle_id,
      reported_issue_id: issue_id
    )
    issue_id
  end
end
