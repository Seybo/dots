# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe FindNextReviewIssue do
  let(:db) { Database.connection }

  it 'selects the oldest unresolved issue linked to the Review' do
    review_id = insert_review(number: 1)
    other_review_id = insert_review(number: 2)
    first_id = insert_issue(source_id: 1)
    second_id = insert_issue(source_id: 2)
    other_id = insert_issue(source_id: 3)
    link_review_issue(review_id, first_id)
    link_review_issue(review_id, second_id)
    link_review_issue(other_review_id, other_id)

    issue = described_class.call(review_id: review_id)

    expect(issue).to include(id: first_id)
  end

  it 'excludes decided issues' do
    review_id = insert_review
    decided_id = insert_issue(source_id: 1, decision: 'approved')
    unresolved_id = insert_issue(source_id: 2)
    link_review_issue(review_id, decided_id)
    link_review_issue(review_id, unresolved_id)

    issue = described_class.call(review_id: review_id)

    expect(issue).to include(id: unresolved_id)
  end

  it 'returns nil when the Review has no unresolved issue' do
    review_id = insert_review
    issue_id = insert_issue(source_id: 1, decision: 'skipped')
    link_review_issue(review_id, issue_id)

    expect(described_class.call(review_id: review_id)).to be_nil
  end

  def insert_review(number: 1)
    db[:reviews].insert(
      created_at: Time.now,
      completed_at: nil,
      project_path: '/project',
      number: number,
      source: 'github',
      branch_name: 'feature',
      starting_commit_sha: nil,
      original_base_ref: 'origin/main',
      original_base_commit_sha: 'base-sha',
      active_base_ref: 'origin/main',
      active_base_commit_sha: 'base-sha',
      state: 'manager_issue_selection',
      final_commit_sha: nil
    )
  end

  def insert_issue(source_id:, decision: nil)
    db[:reported_issues].insert(
      created_at: Time.now,
      project_path: '/project',
      source: 'github',
      source_id: source_id.to_s,
      body: "Issue #{source_id}.",
      decision: decision
    )
  end

  def link_review_issue(review_id, issue_id)
    db[:review_issues].insert(
      created_at: Time.now,
      review_id: review_id,
      reported_issue_id: issue_id
    )
  end
end
