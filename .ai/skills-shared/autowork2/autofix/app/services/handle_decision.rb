# frozen_string_literal: true

class HandleDecision
  include ServiceObject

  arguments :issue_id, :decision

  def call
    StoreDecision.call(issue_id: issue_id, decision: decision)
    RenderDecision.call(decision: decision, next_action: resume_review)
  end

  private

  def review
    @review ||= Database.connection[:reviews].
                join(:review_issues, review_id: :id).
                where(Sequel[:review_issues][:reported_issue_id] => issue_id).
                select_all(:reviews).
                first
  end

  def resume_review
    ResumeReview.call(task_id: review.fetch(:task_id))
  end
end
