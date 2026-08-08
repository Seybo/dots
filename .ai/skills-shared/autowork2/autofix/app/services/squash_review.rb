# frozen_string_literal: true

class SquashReview
  include ServiceObject

  arguments :review_id, :project_path

  def call
    validate_review
    ValidateCleanGitState.call(project_path: project_path)
    ValidateReviewCommitSequence.call(review_id: review_id)
    final_commit_sha = squash
    "Review #{review.fetch(:number)} squashed locally.\n" \
      "Final commit: #{final_commit_sha} Review #{review.fetch(:number)}\n" \
      'Push: not performed.'
  end

  private

  def validate_review
    raise "Review #{review.fetch(:number)} belongs to another project" unless same_project?
    return if review.fetch(:state) == 'completed' && !review.fetch(:completed_at).nil?

    raise "Review #{review.fetch(:number)} is not completed"
  end

  def same_project?
    File.realpath(review.fetch(:project_path)) == File.realpath(project_path)
  end

  def squash
    SquashGitRange.call(
      project_path: project_path,
      parent_sha: review.fetch(:starting_commit_sha),
      subject: "Review #{review.fetch(:number)}"
    )
  end

  def review
    @review ||= Database.connection[:reviews].where(id: review_id).first
  end
end
