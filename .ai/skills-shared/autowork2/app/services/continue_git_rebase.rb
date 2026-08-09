# frozen_string_literal: true

require 'open3'

class ContinueGitRebase
  include ServiceObject

  arguments :project_path, :branch_name, :active_base_ref, :active_base_commit_sha,
            :boundaries, :target_base_ref, :target_base_commit_sha

  def call
    validate_rebase
    preparation
    capture!('git', '-C', canonical_project_path, 'add', '-A')
    stdout, stderr, status = Open3.capture3(
      'git', '-C', canonical_project_path, '-c', 'core.editor=true', 'rebase', '--continue'
    )
    return { status: :completed, preparation: preparation } if status.success?
    return { status: :conflict, preparation: preparation } if unmerged_paths?

    detail = [stdout.strip, stderr.strip].reject(&:empty?).join("\n")
    raise "git rebase --continue failed with exit #{status.exitstatus}: #{detail}"
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

  def preparation
    @preparation ||= begin
      validate_ancestor(active_base_commit_sha)
      boundaries.each_value { |commit_sha| validate_ancestor(commit_sha) }
      {
        project_path: canonical_project_path,
        branch_name: branch_name,
        active_base_ref: active_base_ref,
        active_base_commit_sha: active_base_commit_sha,
        target_base_ref: target_base_ref,
        target_base_commit_sha: target_base_commit_sha,
        head_commit_sha: original_head_commit_sha,
        boundaries: boundaries,
        boundary_counts: boundary_counts,
        rewrites_commits: true
      }
    end
  end

  def boundary_counts
    @boundary_counts ||= boundaries.to_h do |name, commit_sha|
      count = capture!(
        'git', '-C', canonical_project_path, 'rev-list', '--count',
        "#{commit_sha}..#{original_head_commit_sha}"
      ).strip.to_i
      [name, count]
    end
  end

  def validate_ancestor(commit_sha)
    capture!(
      'git', '-C', canonical_project_path,
      'merge-base', '--is-ancestor', commit_sha, original_head_commit_sha
    )
  end

  def unmerged_paths?
    !capture!(
      'git', '-C', canonical_project_path,
      'diff', '--name-only', '--diff-filter=U'
    ).empty?
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

  def capture!(*command)
    stdout, stderr, status = Open3.capture3(*command)
    return stdout if status.success?

    raise "#{command.join(' ')} failed with exit #{status.exitstatus}: #{stderr.strip}"
  end
end
