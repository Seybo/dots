# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe StoreDecision do
  let(:reported_issues) { Database.connection[:reported_issues] }

  it 'approves the exact issue ID and returns the updated issue' do
    other_id = store_issue(source_id: 1)
    issue_id = store_issue(source_id: 2)

    issue = described_class.call(issue_id: issue_id, decision: 'approved')

    expect(reported_issues.where(id: other_id).get(:decision)).to be_nil
    expect(reported_issues.where(id: issue_id).get(:decision)).to eq('approved')
    expect(issue).to include(id: issue_id, decision: 'approved')
  end

  it 'skips the exact issue ID' do
    issue_id = store_issue(source: 'local', source_id: nil)

    issue = described_class.call(issue_id: issue_id, decision: 'skipped')

    expect(issue).to include(id: issue_id, decision: 'skipped')
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
