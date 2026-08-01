# frozen_string_literal: true

require 'open3'

class PrepareReviewRebase
  include ServiceObject

  arguments :project_path, :branch_name, base_ref: nil

  def call
    validate_review
    validate_branch
    validate_clean_tree
    capture!('git', '-C', canonical_project_path, 'fetch', 'origin')

    head_commit_sha = capture!('git', '-C', canonical_project_path, 'rev-parse', 'HEAD').strip
    validate_ancestor(review.fetch(:active_base_commit_sha), head_commit_sha)
    validate_ancestor(review.fetch(:starting_commit_sha), head_commit_sha)

    preparation(head_commit_sha)
  end

  private

  def validate_review
    raise "No incomplete Review for branch #{branch_name} in #{canonical_project_path}" if review.nil?
    raise "Review #{review.fetch(:number)} has no starting commit" if review.fetch(:starting_commit_sha).nil?
    unless completed_implementation?
      raise "Review #{review.fetch(:number)} has no completed Worker implementation Work Cycle"
    end
    return if incomplete_work_cycle.nil?

    raise "Review #{review.fetch(:number)} has incomplete Work Cycle #{incomplete_work_cycle.fetch(:id)}"
  end

  def validate_branch
    current_branch = capture!('git', '-C', canonical_project_path, 'branch', '--show-current').strip
    return if current_branch == review.fetch(:branch_name)

    raise "Current branch #{current_branch} does not match Review #{review.fetch(:number)} " \
          "branch #{review.fetch(:branch_name)}"
  end

  def validate_clean_tree
    status = capture!('git', '-C', canonical_project_path, 'status', '--porcelain')
    return if status.empty?

    raise "Working tree is not clean in #{canonical_project_path}:\n#{status}"
  end

  def validate_ancestor(ancestor_sha, head_commit_sha)
    capture!(
      'git', '-C', canonical_project_path,
      'merge-base', '--is-ancestor', ancestor_sha, head_commit_sha
    )
  end

  def preparation(head_commit_sha)
    {
      review_id: review.fetch(:id),
      review_number: review.fetch(:number),
      project_path: canonical_project_path,
      branch_name: review.fetch(:branch_name),
      starting_commit_sha: review.fetch(:starting_commit_sha),
      original_base_ref: review.fetch(:original_base_ref),
      original_base_commit_sha: review.fetch(:original_base_commit_sha),
      active_base_ref: review.fetch(:active_base_ref),
      active_base_commit_sha: review.fetch(:active_base_commit_sha),
      target_base_ref: target_base_ref,
      target_base_commit_sha: target_base_commit_sha,
      head_commit_sha: head_commit_sha,
      commits_after_starting_count: commits_after_starting_count(head_commit_sha)
    }
  end

  def review
    return @review if defined?(@review)

    @review = Database.connection[:reviews].
              where(project_path: canonical_project_path, branch_name: branch_name).
              exclude(state: 'completed').
              order(:id).
              first
  end

  def completed_implementation?
    Database.connection[:work_cycles].
      where(review_id: review.fetch(:id), role: 'worker', action: 'implementation').
      exclude(completed_at: nil).
      any?
  end

  def incomplete_work_cycle
    @incomplete_work_cycle ||= Database.connection[:work_cycles].
                               where(review_id: review.fetch(:id), completed_at: nil).
                               order(:id).
                               first
  end

  def target_base_ref
    @target_base_ref ||= base_ref || review.fetch(:active_base_ref)
  end

  def target_base_commit_sha
    @target_base_commit_sha ||= capture!(
      'git', '-C', canonical_project_path, 'rev-parse', "#{target_base_ref}^{commit}"
    ).strip
  end

  def commits_after_starting_count(head_commit_sha)
    capture!(
      'git', '-C', canonical_project_path, 'rev-list', '--count',
      "#{review.fetch(:starting_commit_sha)}..#{head_commit_sha}"
    ).strip.to_i
  end

  def canonical_project_path
    @canonical_project_path ||= File.realpath(project_path)
  end

  def capture!(*command)
    stdout, stderr, status = Open3.capture3(*command)
    return stdout if status.success?

    raise "#{command.join(' ')} failed with exit #{status.exitstatus}: #{stderr.strip}"
  end
end
