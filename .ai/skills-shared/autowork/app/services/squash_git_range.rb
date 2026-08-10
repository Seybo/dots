# frozen_string_literal: true

require 'open3'

class SquashGitRange
  include ServiceObject

  arguments :project_path, :parent_sha, :subject

  def call
    tree_sha = capture!('git', '-C', project_path, 'rev-parse', 'HEAD^{tree}').strip
    final_commit_sha = capture!(
      'git', '-C', project_path, 'commit-tree', tree_sha,
      '-p', parent_sha, '-m', subject
    ).strip
    capture!('git', '-C', project_path, 'reset', '--soft', final_commit_sha)
    final_commit_sha
  end

  private

  def capture!(*command)
    stdout, stderr, status = Open3.capture3(*command)
    return stdout if status.success?

    raise "#{command.join(' ')} failed with exit #{status.exitstatus}: #{stderr.strip}"
  end
end
