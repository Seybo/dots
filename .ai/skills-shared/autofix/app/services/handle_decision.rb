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
    return 'No unresolved issues.' if implementation_work_cycle?

    complete_review
    render(RenderIssue.call(issue: nil))
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

  def implementation_work_cycle?
    Database.connection[:work_cycles].where(
      review_id: review.fetch(:id),
      action: 'implementation'
    ).any?
  end

  def complete_review
    Database.connection[:reviews].where(id: review.fetch(:id)).update(
      state: 'completed',
      completed_at: Time.now
    )
  end

  def render(next_action)
    RenderDecision.call(decision: decision, next_action: next_action)
  end
end
