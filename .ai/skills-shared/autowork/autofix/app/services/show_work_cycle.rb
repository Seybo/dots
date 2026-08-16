# frozen_string_literal: true

require 'json'

class ShowWorkCycle
  include ServiceObject

  arguments :work_cycle_id

  def call
    JSON.generate(
      work_cycle_id: work_cycle.fetch(:id),
      review_id: review.fetch(:id),
      review_number: review.fetch(:number),
      role: work_cycle.fetch(:role),
      action: work_cycle.fetch(:action),
      task_path: review_context.fetch(:task).fetch(:task_path),
      project_path: review_context.fetch(:project_path),
      branch_name: review_context.fetch(:branch_name),
      feature_path: review_context.fetch(:feature_path),
      feature_text: review_context.fetch(:feature_text),
      starting_commit_sha: review.fetch(:starting_commit_sha),
      active_base_ref: branch.fetch('active_base_ref'),
      active_base_commit_sha: branch.fetch('active_base_commit_sha'),
      inputs: issues(:work_cycle_inputs),
      reported_issues: issues(:work_cycle_reported_issues)
    )
  end

  private

  def work_cycle
    @work_cycle ||= Database.readonly_connection[:work_cycles].where(id: work_cycle_id).first
  end

  def review
    @review ||= Database.readonly_connection[:reviews].where(id: work_cycle.fetch(:review_id)).first
  end

  def review_context
    @review_context ||= LoadReviewContext.call(review: review)
  end

  def branch
    @branch ||= review_context.fetch(:config).fetch('branch')
  end

  def issues(link_table)
    Database.readonly_connection[:reported_issues].
      join(link_table, reported_issue_id: :id).
      where(Sequel[link_table][:work_cycle_id] => work_cycle_id).
      select_all(:reported_issues).
      order(Sequel[:reported_issues][:id]).
      all.
      map { |issue| issue.slice(:id, :source, :body, :decision) }
  end
end
