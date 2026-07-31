# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe StoreIssue do
  let(:reported_issues) { Database.connection[:reported_issues] }

  it 'stores one issue with generated fields' do
    id = store_issue
    issue = reported_issues.where(id: id).first

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

    expect(reported_issues.count).to eq(3)
  end

  it 'stores every local issue with no source ID' do
    first_id = store_issue(source: 'local', source_id: nil)
    second_id = store_issue(source: 'local', source_id: nil)

    expect(first_id).not_to eq(second_id)
    expect(reported_issues.where(source: 'local').select_map(:source_id)).to eq([nil, nil])
  end

  it 'updates only the body of an unresolved issue' do
    id = store_issue
    original = reported_issues.where(id: id).first

    store_issue(body: 'Changed body')

    expect(reported_issues.where(id: id).first).to eq(original.merge(body: 'Changed body'))
  end

  it 'does not change a decided issue' do
    id = store_issue
    reported_issues.where(id: id).update(decision: 'approved')
    original = reported_issues.where(id: id).first

    store_issue(body: 'Changed body')

    expect(reported_issues.where(id: id).first).to eq(original)
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
