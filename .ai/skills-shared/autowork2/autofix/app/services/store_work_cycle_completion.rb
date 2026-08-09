# frozen_string_literal: true

class StoreWorkCycleCompletion
  include ServiceObject

  arguments :work_cycle_id, :work_cycle_result

  def call
    Database.connection.transaction(savepoint: true) do
      issue_ids = StoreWorkCycleResult.call(
        work_cycle_id: work_cycle_id,
        project_path: review_context.fetch(:project_path),
        work_cycle_result: work_cycle_result
      )
      link_review_issues(issue_ids)
      Database.connection[:reviews].where(id: work_cycle.fetch(:review_id)).update(state: next_review_state)
    end
  end

  private

  def link_review_issues(issue_ids)
    created_at = Time.now
    issue_ids.each do |issue_id|
      Database.connection[:review_issues].insert(
        created_at: created_at,
        review_id: review.fetch(:id),
        reported_issue_id: issue_id
      )
    end
  end

  def reported_issues
    @reported_issues ||= work_cycle_result.fetch('reported_issues')
  end

  def work_cycle
    @work_cycle ||= Database.connection[:work_cycles].where(id: work_cycle_id).first
  end

  def review
    @review ||= Database.connection[:reviews].where(id: work_cycle.fetch(:review_id)).first
  end

  def review_context
    @review_context ||= LoadReviewContext.call(review: review)
  end

  def next_review_state
    case [work_cycle.fetch(:role), work_cycle.fetch(:action)]
    when %w[worker implementation] then 'reviewer_review'
    when %w[reviewer review] then reviewer_review_state
    when %w[worker review] then reported_issues.empty? ? 'manager_review' : 'manager_issues_assessment'
    when %w[manager review] then reported_issues.empty? ? 'manager_finalizing' : 'manager_issues_assessment'
    else
      raise "Unsupported Work Cycle completion: #{work_cycle.fetch(:role)}/#{work_cycle.fetch(:action)}"
    end
  end

  def reviewer_review_state
    return 'manager_issues_assessment' unless reported_issues.empty?
    return 'manager_review' if worker_review?

    'worker_review'
  end

  def worker_review?
    Database.connection[:work_cycles].where(
      review_id: review.fetch(:id),
      role: 'worker',
      action: 'review'
    ).any?
  end
end
