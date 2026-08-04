# frozen_string_literal: true

require 'open3'

class RebaseReview
  include ServiceObject

  arguments :project_path, :branch_name, base_ref: nil

  def call
    validate_no_rebase
    @preparation = PrepareReviewRebase.call(
      project_path: canonical_project_path,
      branch_name: branch_name,
      base_ref: base_ref
    )
    stdout, stderr, status = capture(
      'git', '-C', canonical_project_path, 'rebase', '--onto',
      preparation.fetch(:target_base_commit_sha),
      preparation.fetch(:active_base_commit_sha)
    )
    return CompleteReviewRebase.call(preparation: preparation) if status.success?
    return conflict_control if unmerged_paths?

    raise command_error(status, stdout, stderr)
  end

  private

  attr_reader :preparation

  def validate_no_rebase
    return unless rebase_in_progress?

    raise 'A Git rebase is already in progress; run git rebase --abort before starting again'
  end

  def rebase_in_progress?
    %w[rebase-merge rebase-apply].any? { |name| Dir.exist?(File.join(git_directory, name)) }
  end

  def conflict_control
    "RebaseConflict #{preparation.fetch(:review_id)}\n" \
      "RebaseTargetRef #{preparation.fetch(:target_base_ref)}\n" \
      "RebaseTargetCommit #{preparation.fetch(:target_base_commit_sha)}"
  end

  def unmerged_paths?
    !capture!('git', '-C', canonical_project_path, 'diff', '--name-only', '--diff-filter=U').empty?
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
    "git rebase failed with exit #{status.exitstatus}: #{detail}"
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
