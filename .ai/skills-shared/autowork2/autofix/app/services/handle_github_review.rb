# frozen_string_literal: true

require 'json'

class HandleGithubReview
  include ServiceObject

  arguments :json_path, :project_path, :task_path

  def call
    validate_review_input
    return 'No issues found.' if unassigned_issue_data.empty?

    review_id = StoreReview.call(
      task_context: task_context,
      source: 'github',
      starting_commit_sha: ValidateCleanGitState.call(project_path: project_path),
      issue_data: unassigned_issue_data
    )
    RenderIssue.call(issue: FindNextReviewIssue.call(review_id: review_id))
  end

  private

  def validate_review_input
    expected = task_context.fetch(:config).fetch('branch')
    unless review_input.fetch('branch_name') == expected.fetch('name')
      raise "GitHub Review branch #{review_input.fetch('branch_name')} does not match Task branch " \
            "#{expected.fetch('name')}"
    end
    return if review_input.fetch('base_ref') == expected.fetch('active_base_ref') &&
              review_input.fetch('base_commit_sha') == expected.fetch('active_base_commit_sha')

    raise "GitHub Review base #{review_input.fetch('base_ref')} @ " \
          "#{review_input.fetch('base_commit_sha')} does not match Task active base " \
          "#{expected.fetch('active_base_ref')} @ #{expected.fetch('active_base_commit_sha')}. " \
          "Run --rebase-base #{review_input.fetch('base_ref')} before importing the Review."
  end

  def task_context
    @task_context ||= LoadCompletedTask.call(task_path: task_path, project_path: project_path)
  end

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
            Sequel[:reported_issues][:project_path] => task_context.fetch(:task).fetch(:project_path),
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
