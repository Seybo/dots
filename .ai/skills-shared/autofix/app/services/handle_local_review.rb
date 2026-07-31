# frozen_string_literal: true

require 'json'

class HandleLocalReview
  include ServiceObject

  arguments :json_path, :project_path

  def call
    return 'No issues found.' if issue_data.empty?

    review_id = StoreReview.call(
      project_path: project_path,
      source: 'local',
      branch_name: review_input.fetch('branch_name'),
      base_ref: review_input.fetch('base_ref'),
      base_commit_sha: review_input.fetch('base_commit_sha'),
      issue_data: issue_data
    )
    RenderIssue.call(issue: FindNextReviewIssue.call(review_id: review_id))
  end

  private

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
