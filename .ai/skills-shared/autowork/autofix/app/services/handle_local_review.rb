# frozen_string_literal: true

require 'json'

class HandleLocalReview
  include ServiceObject

  arguments :json_path, :project_path, :task_path

  def call
    task_context
    return 'No issues found.' if issue_data.empty?

    review_id = StoreReview.call(
      task_context: task_context,
      source: 'local',
      starting_commit_sha: ValidateCleanGitState.call(project_path: project_path),
      issue_data: issue_data
    )
    RenderIssue.call(issue: FindNextReviewIssue.call(review_id: review_id))
  end

  private

  def task_context
    @task_context ||= LoadCompletedTask.call(task_path: task_path, project_path: project_path)
  end

  def issue_data
    issue_bodies.map { |body| { source_id: nil, body: body } }
  end

  def issue_bodies
    @issue_bodies ||= review_input.fetch('issues').tap do |value|
      unless value.is_a?(Array) && value.all? { |body| body.is_a?(String) && !body.strip.empty? }
        raise ArgumentError, 'Local issues must be an array of non-empty strings'
      end
    end
  end

  def review_input
    @review_input ||= JSON.parse(File.read(json_path))
  end
end
