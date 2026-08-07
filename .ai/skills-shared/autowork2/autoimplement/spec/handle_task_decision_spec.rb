# frozen_string_literal: true

require_relative '../../spec/spec_helper'

RSpec.describe HandleTaskDecision do
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
  let(:review_work_cycle_id) do
    db[:work_cycles].insert(
      created_at: Time.now,
      completed_at: Time.now,
      task_id: task_id,
      role: 'reviewer',
      action: 'review'
    )
  end
  let(:issue_id) do
    id = StoreIssue.call(project_path: '/project', source: 'reviewer', body: 'Fix it.')
    db[:work_cycle_reported_issues].insert(
      created_at: Time.now,
      work_cycle_id: review_work_cycle_id,
      reported_issue_id: id
    )
    id
  end

  before do
    allow(ResumeTask).to receive(:call).and_return('Step 1 accepted.')
  end

  it 'stores the decision and resumes the Task that produced the issue' do
    output = described_class.call(issue_id: issue_id, decision: 'skipped')

    expect(db[:reported_issues].where(id: issue_id).get(:decision)).to eq('skipped')
    expect(ResumeTask).to have_received(:call).with(task_id: task_id)
    expect(output).to eq("Decision: skipped\n\nStep 1 accepted.")
  end
end
