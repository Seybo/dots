# frozen_string_literal: true

class StoreReview
  include ServiceObject

  arguments :project_path, :source, :branch_name, :base_ref, :base_commit_sha, :issue_data

  def call
    review_id = nil
    Database.connection.transaction(savepoint: true) do
      issue_ids = store_issues
      review_id = create_review
      link_issues(review_id, issue_ids)
    end
    review_id
  end

  private

  def store_issues
    issue_data.map do |issue|
      StoreIssue.call(
        project_path: project_path,
        source: source,
        source_id: issue.fetch(:source_id),
        body: issue.fetch(:body)
      )
    end
  end

  def create_review
    reviews.insert(
      created_at: Time.now,
      completed_at: nil,
      project_path: project_path,
      number: reviews.where(project_path: project_path).max(:number).to_i + 1,
      source: source,
      branch_name: branch_name,
      starting_commit_sha: nil,
      original_base_ref: base_ref,
      original_base_commit_sha: base_commit_sha,
      active_base_ref: base_ref,
      active_base_commit_sha: base_commit_sha,
      state: 'manager_issue_selection',
      final_commit_sha: nil
    )
  end

  def reviews
    Database.connection[:reviews]
  end

  def link_issues(review_id, issue_ids)
    issue_ids.each do |issue_id|
      Database.connection[:review_issues].insert(
        created_at: Time.now,
        review_id: review_id,
        reported_issue_id: issue_id
      )
    end
  end
end
