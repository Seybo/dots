# frozen_string_literal: true

require 'open3'

class RunGitRebase
  include ServiceObject

  arguments :preparation

  def call
    return :completed unless preparation.fetch(:rewrites_commits)

    stdout, stderr, status = Open3.capture3(
      'git', '-C', preparation.fetch(:project_path), 'rebase', '--onto',
      preparation.fetch(:target_base_commit_sha),
      preparation.fetch(:active_base_commit_sha)
    )
    return :completed if status.success?
    return :conflict if unmerged_paths?

    detail = [stdout.strip, stderr.strip].reject(&:empty?).join("\n")
    raise "git rebase failed with exit #{status.exitstatus}: #{detail}"
  end

  private

  def unmerged_paths?
    stdout, stderr, status = Open3.capture3(
      'git', '-C', preparation.fetch(:project_path),
      'diff', '--name-only', '--diff-filter=U'
    )
    unless status.success?
      raise "git diff --name-only --diff-filter=U failed with exit #{status.exitstatus}: #{stderr.strip}"
    end

    !stdout.empty?
  end
end
