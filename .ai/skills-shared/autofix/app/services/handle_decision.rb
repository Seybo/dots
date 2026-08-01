# frozen_string_literal: true

class HandleDecision
  include ServiceObject

  arguments :issue_id, :decision

  def call
    StoreDecision.call(issue_id: issue_id, decision: decision)
    next_issue = FindNextReviewIssue.call(review_id: review.fetch(:id))
    return render(RenderIssue.call(issue: next_issue)) unless next_issue.nil?

    work_cycle_id = StartImplementationWorkCycle.call(review_id: review.fetch(:id))
    return render(RenderWorkCycleHandoff.call(work_cycle_id: work_cycle_id)) unless work_cycle_id.nil?

    settle_assessment
  end

  private

  def review
    return @review if defined?(@review)

    @review = Database.connection[:reviews].
              join(:review_issues, review_id: :id).
              where(Sequel[:review_issues][:reported_issue_id] => issue_id).
              select_all(:reviews).
              first
  end

  def settle_assessment
    if latest_completed_work_cycle.nil?
      complete_review
      return render(RenderIssue.call(issue: nil))
    end

    if worker_review?
      move_to_manager_review
      return RenderIssue.call(issue: nil)
    end

    work_cycle_id = StartWorkerReviewWorkCycle.call(review_id: review.fetch(:id))
    render(RenderWorkCycleHandoff.call(work_cycle_id: work_cycle_id))
  end

  def latest_completed_work_cycle
    @latest_completed_work_cycle ||= Database.connection[:work_cycles].
                                     where(review_id: review.fetch(:id)).
                                     exclude(completed_at: nil).
                                     order(:id).
                                     last
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

  def render(next_action)
    RenderDecision.call(decision: decision, next_action: next_action)
  end
end
