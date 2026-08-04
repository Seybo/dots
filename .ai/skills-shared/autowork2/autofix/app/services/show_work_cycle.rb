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
      project_path: review.fetch(:project_path),
      branch_name: review.fetch(:branch_name),
      starting_commit_sha: review.fetch(:starting_commit_sha),
      active_base_ref: review.fetch(:active_base_ref),
      active_base_commit_sha: review.fetch(:active_base_commit_sha),
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
