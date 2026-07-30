# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe NextIssue do
  let(:issues) { Database.connection[:reported_issues] }

  it 'selects the oldest unresolved GitHub issue from the active IDs' do
    first_id = store_issue(source_id: 1)
    store_issue(source_id: 2)
    store_issue(project_path: '/other-project', source_id: 1)
    store_issue(source: 'local', source_id: nil)

    issue = described_class.call(
      project_path: '/project',
      source: 'github',
      source_ids: [2, 1]
    )

    expect(issue.fetch(:id)).to eq(first_id)
  end

  it 'selects the oldest unresolved local issue for the project' do
    first_id = store_issue(source: 'local', source_id: nil)
    store_issue(source: 'local', source_id: nil)
    store_issue(project_path: '/other-project', source: 'local', source_id: nil)

    issue = described_class.call(project_path: '/project', source: 'local')

    expect(issue.fetch(:id)).to eq(first_id)
  end

  it 'excludes decided issues' do
    approved_id = store_issue(source_id: 1)
    skipped_id = store_issue(source_id: 2)
    unresolved_id = store_issue(source_id: 3)
    issues.where(id: approved_id).update(decision: 'approved')
    issues.where(id: skipped_id).update(decision: 'skipped')

    issue = described_class.call(
      project_path: '/project',
      source: 'github',
      source_ids: [1, 2, 3]
    )

    expect(issue.fetch(:id)).to eq(unresolved_id)
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
