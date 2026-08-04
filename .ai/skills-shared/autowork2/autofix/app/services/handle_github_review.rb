# frozen_string_literal: true

require 'json'

class HandleGithubReview
  include ServiceObject

  arguments :json_path, :project_path

  def call
    return 'No issues found.' if unassigned_issue_data.empty?

    review_id = StoreReview.call(
      project_path: project_path,
      source: 'github',
      branch_name: review_input.fetch('branch_name'),
      base_ref: review_input.fetch('base_ref'),
      base_commit_sha: review_input.fetch('base_commit_sha'),
      issue_data: unassigned_issue_data
    )
    RenderIssue.call(issue: FindNextReviewIssue.call(review_id: review_id))
  end

  private

  def unassigned_issue_data
    normalized_issue_data.reject { |issue| linked_source_ids.include?(issue.fetch(:source_id)) }
  end

  def normalized_issue_data
    @normalized_issue_data ||= review_input.fetch('issues').map do |issue|
      { source_id: issue.fetch('source_id').to_s, body: issue.fetch('body') }
    end
  end

  def linked_source_ids
    @linked_source_ids ||= begin
      source_ids = normalized_issue_data.map { |issue| issue.fetch(:source_id) }
      if source_ids.empty?
        []
      else
        Database.connection[:reported_issues].
          join(:review_issues, reported_issue_id: :id).
          where(
            Sequel[:reported_issues][:project_path] => project_path,
            Sequel[:reported_issues][:source] => 'github',
            Sequel[:reported_issues][:source_id] => source_ids
          ).
          select_map(Sequel[:reported_issues][:source_id])
      end
    end
  end

  def review_input
    @review_input ||= JSON.parse(File.read(json_path))
  end
end
