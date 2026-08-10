# frozen_string_literal: true

require 'open3'

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

    validate_branch
    return if review.fetch(:state) == 'completed' && !review.fetch(:completed_at).nil?

    raise "Review #{review.fetch(:number)} is not completed"
  end

  def same_project?
    File.realpath(review_context.fetch(:project_path)) == File.realpath(project_path)
  end

  def validate_branch
    command = ['git', '-C', project_path, 'branch', '--show-current']
    stdout, stderr, status = Open3.capture3(*command)
    raise "#{command.join(' ')} failed with exit #{status.exitstatus}: #{stderr.strip}" unless status.success?

    current_branch = stdout.strip
    return if current_branch == review_context.fetch(:branch_name)

    raise "Review #{review.fetch(:number)} branch mismatch: expected #{review_context.fetch(:branch_name)}, " \
          "got #{current_branch}"
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

  def review_context
    @review_context ||= LoadReviewContext.call(review: review)
  end
end
