# frozen_string_literal: true

class FinalizeReview
  include ServiceObject

  arguments :review_id

  def call
    result = RunFinalChecks.call(
      project_path: project_path,
      starting_commit_sha: review.fetch(:starting_commit_sha)
    )
    output = result.fetch(:output)
    return output unless result.fetch(:is_passing)

    ValidateCleanGitState.call(project_path: project_path)
    ValidateReviewCommitSequence.call(review_id: review_id)
    complete_review
    "#{output}\nReview #{review.fetch(:number)} completed locally.\n" \
      "Push: not performed.\n" \
      "AutoFixSquash #{review_id}"
  end

  private

  def review
    @review ||= Database.connection[:reviews].where(id: review_id).first
  end

  def project_path
    review_context.fetch(:project_path)
  end

  def review_context
    @review_context ||= LoadReviewContext.call(review: review)
  end

  def complete_review
    Database.connection[:reviews].where(id: review_id).update(
      state: 'completed',
      completed_at: Time.now
    )
  end
end
