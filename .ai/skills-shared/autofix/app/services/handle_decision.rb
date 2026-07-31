# frozen_string_literal: true

class HandleDecision
  include ServiceObject

  arguments :issue_id, :decision

  def call
    StoreDecision.call(issue_id: issue_id, decision: decision)
    next_issue = FindNextReviewIssue.call(review_id: review.fetch(:id))
    return render(RenderIssue.call(issue: next_issue)) unless next_issue.nil?

    if all_skipped?
      complete_review
      render(RenderIssue.call(issue: nil))
    else
      work_cycle_id = StartImplementationWorkCycle.call(review_id: review.fetch(:id))
      render(RenderWorkCycleHandoff.call(work_cycle_id: work_cycle_id))
    end
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

  def all_skipped?
    Database.connection[:reported_issues].
      join(:review_issues, reported_issue_id: :id).
      where(
        Sequel[:review_issues][:review_id] => review.fetch(:id),
        Sequel[:reported_issues][:decision] => 'approved'
      ).
      empty?
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
