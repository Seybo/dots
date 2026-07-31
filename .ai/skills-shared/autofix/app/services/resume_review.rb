# frozen_string_literal: true

require 'json'

class ResumeReview
  include ServiceObject

  arguments :project_path, :branch_name

  def call
    return 'No incomplete Review.' if review.nil?
    return resume_manager_selection if review.fetch(:state) == 'manager_issue_selection'
    return resume_implementation if review.fetch(:state) == 'worker_implementation'
    return resume_reviewer_review if review.fetch(:state) == 'reviewer_review'
    return resume_worker_review if review.fetch(:state) == 'worker_review'

    raise "Cannot resume Review #{review.fetch(:number)} from state #{review.fetch(:state)}"
  end

  private

  def review
    return @review if defined?(@review)

    @review = Database.connection[:reviews].
              where(project_path: project_path, branch_name: branch_name).
              exclude(state: 'completed').
              order(:id).
              first
  end

  def resume_manager_selection
    issue = FindNextReviewIssue.call(review_id: review.fetch(:id))
    return RenderIssue.call(issue: issue) unless issue.nil?

    work_cycle_id = StartImplementationWorkCycle.call(review_id: review.fetch(:id))
    RenderWorkCycleHandoff.call(work_cycle_id: work_cycle_id)
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

    completed_work_cycle = Database.connection[:work_cycles].
                           where(
                             review_id: review.fetch(:id),
                             role: 'reviewer',
                             action: 'review'
                           ).
                           exclude(completed_at: nil).
                           order(:id).
                           last
    return render_completed_review(completed_work_cycle) unless completed_work_cycle.nil?

    implementation_work_cycle = Database.connection[:work_cycles].
                                where(
                                  review_id: review.fetch(:id),
                                  role: 'worker',
                                  action: 'implementation'
                                ).
                                exclude(completed_at: nil).
                                exclude(commit_sha: nil).
                                order(:id).
                                last
    if implementation_work_cycle.nil?
      raise "Review #{review.fetch(:number)} has no completed implementation Work Cycle"
    end

    work_cycle_id = StartReviewerReviewWorkCycle.call(
      previous_work_cycle_id: implementation_work_cycle.fetch(:id)
    )
    RenderWorkCycleHandoff.call(work_cycle_id: work_cycle_id)
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

    reviewer_work_cycle = Database.connection[:work_cycles].
                          where(
                            review_id: review.fetch(:id),
                            role: 'reviewer',
                            action: 'review'
                          ).
                          exclude(completed_at: nil).
                          order(:id).
                          last
    if reviewer_work_cycle.nil?
      raise "Review #{review.fetch(:number)} has no completed Reviewer review Work Cycle"
    end

    reviewer_result = JSON.parse(reviewer_work_cycle.fetch(:result))
    unless reviewer_result.fetch('findings').empty?
      raise "Review #{review.fetch(:number)} has no passing Reviewer review Work Cycle"
    end

    work_cycle_id = StartWorkerReviewWorkCycle.call(
      previous_work_cycle_id: reviewer_work_cycle.fetch(:id)
    )
    RenderWorkCycleHandoff.call(work_cycle_id: work_cycle_id)
  end

  def render_completed_review(work_cycle)
    result = JSON.parse(work_cycle.fetch(:result))
    findings = result.fetch('findings')
    if findings.empty?
      raise "Review #{review.fetch(:number)} has a passing Reviewer result in reviewer_review state"
    end

    RenderWorkCycleResult.call(
      work_cycle_id: work_cycle.fetch(:id),
      role: work_cycle.fetch(:role),
      action: work_cycle.fetch(:action),
      findings: findings
    )
  end
end
