# frozen_string_literal: true

require 'open3'

class ContinueReviewRebase
  include ServiceObject

  arguments :project_path, :branch_name, :target_base_ref, :target_base_commit_sha

  def call
    validate_rebase
    build_preparation
    capture!('git', '-C', canonical_project_path, 'add', '-A')
    stdout, stderr, status = capture(
      'git', '-C', canonical_project_path, '-c', 'core.editor=true', 'rebase', '--continue'
    )
    return CompleteReviewRebase.call(preparation: preparation) if status.success?
    return conflict_control if unmerged_paths?

    raise command_error(status, stdout, stderr)
  end

  private

  def validate_rebase
    raise 'No Git rebase is in progress' if rebase_directory.nil?
    unless rebase_branch_name == branch_name
      raise "In-progress rebase branch #{rebase_branch_name} does not match retained branch #{branch_name}"
    end
    return if rebase_target_commit_sha == target_base_commit_sha

    raise "Rebase target #{rebase_target_commit_sha} does not match retained target #{target_base_commit_sha}"
  end

  def build_preparation
    raise "No incomplete Review for branch #{branch_name} in #{canonical_project_path}" if review.nil?
    raise "Review #{review.fetch(:number)} has no starting commit" if review.fetch(:starting_commit_sha).nil?
    unless completed_implementation?
      raise "Review #{review.fetch(:number)} has no completed Worker implementation Work Cycle"
    end
    return preparation if incomplete_work_cycle.nil?

    raise "Review #{review.fetch(:number)} has incomplete Work Cycle #{incomplete_work_cycle.fetch(:id)}"
  end

  def preparation
    @preparation ||= {
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
      head_commit_sha: original_head_commit_sha,
      commits_after_starting_count: commits_after_starting_count
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

  def commits_after_starting_count
    validate_ancestor(review.fetch(:active_base_commit_sha))
    validate_ancestor(review.fetch(:starting_commit_sha))
    capture!(
      'git', '-C', canonical_project_path, 'rev-list', '--count',
      "#{review.fetch(:starting_commit_sha)}..#{original_head_commit_sha}"
    ).strip.to_i
  end

  def validate_ancestor(commit_sha)
    capture!(
      'git', '-C', canonical_project_path,
      'merge-base', '--is-ancestor', commit_sha, original_head_commit_sha
    )
  end

  def conflict_control
    "RebaseConflict #{preparation.fetch(:review_id)}\n" \
      "RebaseTargetRef #{target_base_ref}\n" \
      "RebaseTargetCommit #{target_base_commit_sha}"
  end

  def unmerged_paths?
    !capture!('git', '-C', canonical_project_path, 'diff', '--name-only', '--diff-filter=U').empty?
  end

  def rebase_branch_name
    File.read(File.join(rebase_directory, 'head-name')).strip.delete_prefix('refs/heads/')
  end

  def rebase_target_commit_sha
    File.read(File.join(rebase_directory, 'onto')).strip
  end

  def original_head_commit_sha
    @original_head_commit_sha ||= File.read(File.join(rebase_directory, 'orig-head')).strip
  end

  def rebase_directory
    return @rebase_directory if defined?(@rebase_directory)

    @rebase_directory = %w[rebase-merge rebase-apply].
                        map { |name| File.join(git_directory, name) }.
                        find { |path| Dir.exist?(path) }
  end

  def git_directory
    @git_directory ||= capture!(
      'git', '-C', canonical_project_path, 'rev-parse', '--absolute-git-dir'
    ).strip
  end

  def canonical_project_path
    @canonical_project_path ||= File.realpath(project_path)
  end

  def command_error(status, stdout, stderr)
    detail = [stdout.strip, stderr.strip].reject(&:empty?).join("\n")
    "git rebase --continue failed with exit #{status.exitstatus}: #{detail}"
  end

  def capture(*command)
    Open3.capture3(*command)
  end

  def capture!(*command)
    stdout, stderr, status = capture(*command)
    return stdout if status.success?

    raise "#{command.join(' ')} failed with exit #{status.exitstatus}: #{stderr.strip}"
  end
end
