# frozen_string_literal: true

require 'json'

class StoreWorkCycleCompletion
  include ServiceObject

  arguments :work_cycle_id, :work_cycle_result, commit_sha: nil

  def call
    completed_at = Time.now
    Database.connection.transaction(savepoint: true) do
      store_completion(completed_at)
      store_findings(completed_at)
      Database.connection[:reviews].where(id: work_cycle.fetch(:review_id)).update(state: next_review_state)
    end
  end

  private

  def store_completion(completed_at)
    Database.connection[:work_cycles].where(id: work_cycle_id).update(
      completed_at: completed_at,
      result: JSON.generate(work_cycle_result),
      provider: work_cycle_result.fetch('provider'),
      model: work_cycle_result.fetch('model'),
      reasoning_level: work_cycle_result.fetch('reasoning_level'),
      commit_sha: commit_sha
    )
  end

  def store_findings(created_at)
    return unless stores_findings?

    findings.each do |body|
      issue_id = StoreIssue.call(
        project_path: review.fetch(:project_path),
        source: work_cycle.fetch(:role),
        body: body
      )
      link_finding(issue_id, created_at)
    end
  end

  def stores_findings?
    work_cycle.fetch(:action) == 'review' && %w[worker reviewer].include?(work_cycle.fetch(:role))
  end

  def link_finding(issue_id, created_at)
    Database.connection[:review_issues].insert(
      created_at: created_at,
      review_id: review.fetch(:id),
      reported_issue_id: issue_id
    )
    Database.connection[:work_cycle_findings].insert(
      created_at: created_at,
      work_cycle_id: work_cycle.fetch(:id),
      reported_issue_id: issue_id
    )
  end

  def findings
    @findings ||= work_cycle_result.fetch('findings')
  end

  def work_cycle
    @work_cycle ||= Database.connection[:work_cycles].where(id: work_cycle_id).first
  end

  def review
    @review ||= Database.connection[:reviews].where(id: work_cycle.fetch(:review_id)).first
  end

  def next_review_state
    case [work_cycle.fetch(:role), work_cycle.fetch(:action)]
    when %w[worker implementation] then 'reviewer_review'
    when %w[reviewer review] then findings.empty? ? 'worker_review' : 'manager_finding_selection'
    when %w[worker review] then findings.empty? ? 'manager_review' : 'manager_finding_selection'
    when %w[manager review] then 'manager_finalizing'
    else
      raise "Unsupported Work Cycle completion: #{work_cycle.fetch(:role)}/#{work_cycle.fetch(:action)}"
    end
  end
end
