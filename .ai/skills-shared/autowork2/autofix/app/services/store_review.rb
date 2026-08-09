# frozen_string_literal: true

class StoreReview
  include ServiceObject

  arguments :task_context, :source, :starting_commit_sha, :issue_data

  def call
    Database.connection.transaction(savepoint: true) do
      issue_ids = store_issues
      review_id = create_review
      link_issues(review_id, issue_ids)
      review_id
    end
  end

  private

  def store_issues
    issue_data.map do |issue|
      StoreIssue.call(
        project_path: task.fetch(:project_path),
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
      number: reviews.where(task_id: task.fetch(:id)).max(:number).to_i + 1,
      source: source,
      starting_commit_sha: starting_commit_sha,
      state: 'manager_issues_assessment',
      task_id: task.fetch(:id)
    )
  end

  def task
    task_context.fetch(:task)
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
