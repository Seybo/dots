# frozen_string_literal: true

class ResumeReview
  include ServiceObject

  arguments :project_path, :branch_name

  def call
    return 'No incomplete Review.' if review.nil?
    return resume_active_work if review.fetch(:state) != 'manager_finalizing'

    FinalizeReview.call(review_id: review.fetch(:id))
  end

  private

  def resume_active_work
    return resume_issues_assessment if review.fetch(:state) == 'manager_issues_assessment'
    return resume_implementation if review.fetch(:state) == 'worker_implementation'
    return resume_reviewer_review if review.fetch(:state) == 'reviewer_review'
    return resume_worker_review if review.fetch(:state) == 'worker_review'
    return resume_manager_review if review.fetch(:state) == 'manager_review'

    raise "Cannot resume Review #{review.fetch(:number)} from state #{review.fetch(:state)}"
  end

  def review
    return @review if defined?(@review)

    @review = Database.connection[:reviews].
              where(project_path: project_path, branch_name: branch_name).
              exclude(state: 'completed').
              order(:id).
              first
  end

  def resume_issues_assessment
    issue = FindNextReviewIssue.call(review_id: review.fetch(:id))
    return RenderIssue.call(issue: issue) unless issue.nil?

    work_cycle_id = StartImplementationWorkCycle.call(review_id: review.fetch(:id))
    return RenderWorkCycleHandoff.call(work_cycle_id: work_cycle_id) unless work_cycle_id.nil?

    settle_assessment
  end

  def settle_assessment
    if latest_completed_work_cycle.nil?
      complete_review
      return RenderIssue.call(issue: nil)
    end

    if manager_review?
      move_to_manager_finalizing
      return FinalizeReview.call(review_id: review.fetch(:id))
    end

    if worker_review?
      move_to_manager_review
      return RenderIssue.call(issue: nil)
    end

    work_cycle_id = StartWorkerReviewWorkCycle.call(review_id: review.fetch(:id))
    RenderWorkCycleHandoff.call(work_cycle_id: work_cycle_id)
  end

  def manager_review?
    [latest_completed_work_cycle.fetch(:role), latest_completed_work_cycle.fetch(:action)] ==
      %w[manager review]
  end

  def worker_review?
    Database.connection[:work_cycles].where(
      review_id: review.fetch(:id),
      role: 'worker',
      action: 'review'
    ).any?
  end

  def complete_review
    Database.connection[:reviews].where(id: review.fetch(:id)).update(
      state: 'completed',
      completed_at: Time.now
    )
  end

  def move_to_manager_review
    Database.connection[:reviews].where(id: review.fetch(:id)).update(state: 'manager_review')
  end

  def move_to_manager_finalizing
    Database.connection[:reviews].where(id: review.fetch(:id)).update(state: 'manager_finalizing')
  end

  def resume_implementation
    work_cycle = Database.connection[:work_cycles].
                 where(
                   review_id: review.fetch(:id),
                   role: 'worker',
                   action: 'implementation',
                   completed_at: nil
                 ).
                 order(:id).
                 last
    raise "Review #{review.fetch(:number)} has no incomplete implementation Work Cycle" if work_cycle.nil?

    "WaitWorkCycle #{work_cycle.fetch(:id)}"
  end

  def resume_reviewer_review
    work_cycle = Database.connection[:work_cycles].
                 where(
                   review_id: review.fetch(:id),
                   role: 'reviewer',
                   action: 'review',
                   completed_at: nil
                 ).
                 order(:id).
                 last
    return "WaitWorkCycle #{work_cycle.fetch(:id)}" unless work_cycle.nil?

    ensure_latest_implementation
    work_cycle_id = StartReviewerReviewWorkCycle.call(review_id: review.fetch(:id))
    RenderWorkCycleHandoff.call(work_cycle_id: work_cycle_id)
  end

  def ensure_latest_implementation
    return if [latest_completed_work_cycle.fetch(:role), latest_completed_work_cycle.fetch(:action)] ==
              %w[worker implementation]

    raise "Review #{review.fetch(:number)} latest completed Work Cycle is not a Worker implementation"
  end

  def latest_completed_work_cycle
    @latest_completed_work_cycle ||= Database.connection[:work_cycles].
                                     where(review_id: review.fetch(:id)).
                                     exclude(completed_at: nil).
                                     order(:id).
                                     last
  end

  def resume_worker_review
    work_cycle = Database.connection[:work_cycles].
                 where(
                   review_id: review.fetch(:id),
                   role: 'worker',
                   action: 'review',
                   completed_at: nil
                 ).
                 order(:id).
                 last
    return "WaitWorkCycle #{work_cycle.fetch(:id)}" unless work_cycle.nil?

    ensure_latest_reviewer_review
    work_cycle_id = StartWorkerReviewWorkCycle.call(review_id: review.fetch(:id))
    RenderWorkCycleHandoff.call(work_cycle_id: work_cycle_id)
  end

  def ensure_latest_reviewer_review
    return if [latest_completed_work_cycle.fetch(:role), latest_completed_work_cycle.fetch(:action)] ==
              %w[reviewer review]

    raise "Review #{review.fetch(:number)} latest completed Work Cycle is not a Reviewer review"
  end

  def resume_manager_review
    work_cycle = Database.connection[:work_cycles].
                 where(
                   review_id: review.fetch(:id),
                   role: 'manager',
                   action: 'review',
                   completed_at: nil
                 ).
                 order(:id).
                 last
    work_cycle_id = work_cycle&.fetch(:id) || StartManagerReviewWorkCycle.call(review_id: review.fetch(:id))
    RenderWorkCycleHandoff.call(work_cycle_id: work_cycle_id)
  end
end
