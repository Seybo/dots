# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe StoreIssue do
  let(:issues) { Database.connection[:reported_issues] }

  it 'stores one issue with generated fields' do
    id = store_issue
    issue = issues.where(id: id).first

    expect(issue).to include(
      id: id,
      project_path: '/project',
      source: 'github',
      source_id: '1',
      body: 'Fix the write order.',
      decision: nil
    )
    expect(issue.fetch(:created_at)).to be_a(Time)
  end

  it 'retains issues from different projects and fetches' do
    store_issue
    store_issue(project_path: '/other-project')
    store_issue(source_id: 2)

    expect(issues.count).to eq(3)
  end

  it 'updates only the body of an unresolved issue' do
    id = store_issue
    original = issues.where(id: id).first

    store_issue(body: 'Changed body')

    expect(issues.where(id: id).first).to eq(original.merge(body: 'Changed body'))
  end

  it 'does not change a decided issue' do
    id = store_issue
    issues.where(id: id).update(decision: 'approved')
    original = issues.where(id: id).first

    store_issue(body: 'Changed body')

    expect(issues.where(id: id).first).to eq(original)
  end

  def store_issue(overrides = {})
    attributes = {
      project_path: '/project',
      source: 'github',
      source_id: 1,
      body: 'Fix the write order.'
    }.merge(overrides)

    described_class.call(**attributes)
  end
end
