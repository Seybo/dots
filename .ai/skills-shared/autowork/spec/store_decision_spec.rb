# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe StoreDecision do
  let(:reported_issues) { Database.connection[:reported_issues] }

  it 'approves the exact issue ID and returns the updated issue' do
    other_id = store_issue(source_id: 1)
    issue_id = store_issue(source_id: 2)

    issue = described_class.call(
      issue_id: issue_id,
      decision: 'approved',
      reason: 'The write order loses data.'
    )

    expect(reported_issues.where(id: other_id).get(:decision)).to be_nil
    expect(reported_issues.where(id: issue_id).first).to include(
      decision: 'approved',
      decision_reason: 'The write order loses data.'
    )
    expect(issue).to include(
      id: issue_id,
      decision: 'approved',
      decision_reason: 'The write order loses data.'
    )
  end

  it 'skips the exact issue ID' do
    issue_id = store_issue(source: 'local', source_id: nil)

    issue = described_class.call(
      issue_id: issue_id,
      decision: 'skipped',
      reason: '  No affected data exists.  '
    )

    expect(issue).to include(
      id: issue_id,
      decision: 'skipped',
      decision_reason: '  No affected data exists.  '
    )
  end

  it 'rejects a blank reason without storing the decision' do
    issue_id = store_issue

    expect do
      described_class.call(issue_id: issue_id, decision: 'approved', reason: " \n\t")
    end.to raise_error(ArgumentError, 'Decision reason cannot be empty')
    expect(reported_issues.where(id: issue_id).first).to include(
      decision: nil,
      decision_reason: nil
    )
  end

  def store_issue(overrides = {})
    attributes = {
      project_path: '/project',
      source: 'github',
      source_id: 1,
      body: 'Fix the write order.'
    }.merge(overrides)

    StoreIssue.call(**attributes)
  end
end
