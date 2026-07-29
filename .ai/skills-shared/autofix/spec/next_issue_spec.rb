# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe NextIssue do
  let(:issues) { Database.connection[:reported_issues] }

  it 'selects an unresolved issue from the active project and source IDs' do
    github_id = store_issue(source_id: 1)
    approved_id = store_issue(source_id: 2)
    skipped_id = store_issue(source_id: 3)
    store_issue(project_path: '/other-project', source_id: 1)
    store_issue(source: 'local', source_id: 1)
    issues.where(id: approved_id).update(decision: 'approved')
    issues.where(id: skipped_id).update(decision: 'skipped')

    issue = described_class.call(
      project_path: '/project',
      source: 'github',
      source_ids: [1, 2, 3]
    )

    expect(issue.fetch(:id)).to eq(github_id)
  end

  it 'returns nil when no active issue is unresolved' do
    store_issue(source_id: 1)

    issue = described_class.call(
      project_path: '/project',
      source: 'github',
      source_ids: [2]
    )

    expect(issue).to be_nil
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
