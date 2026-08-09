# frozen_string_literal: true

require 'open3'

class ValidateReviewCommitSequence
  include ServiceObject

  arguments :review_id

  def call
    return if actual_subjects == expected_subjects

    raise "Review #{review.fetch(:number)} commit sequence does not match its implementation Work Cycles"
  end

  private

  def actual_subjects
    capture!(
      'git', '-C', review_context.fetch(:project_path), 'log', '--reverse', '--format=%s',
      "#{review.fetch(:starting_commit_sha)}..HEAD"
    ).lines(chomp: true)
  end

  def expected_subjects
    Database.connection[:work_cycles].
      where(review_id: review_id, role: 'worker', action: 'implementation').
      exclude(completed_at: nil).
      order(:id).
      select_map(:id).
      map { |work_cycle_id| "Work cycle #{work_cycle_id}" }
  end

  def review
    @review ||= Database.connection[:reviews].where(id: review_id).first
  end

  def review_context
    @review_context ||= LoadReviewContext.call(review: review)
  end

  def capture!(*command)
    stdout, stderr, status = Open3.capture3(*command)
    return stdout if status.success?

    raise "#{command.join(' ')} failed with exit #{status.exitstatus}: #{stderr.strip}"
  end
end
