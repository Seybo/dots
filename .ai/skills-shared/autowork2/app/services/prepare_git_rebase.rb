# frozen_string_literal: true

require 'open3'

class PrepareGitRebase
  include ServiceObject

  arguments :project_path, :branch_name, :active_base_ref, :active_base_commit_sha, :boundaries, base_ref: nil

  def call
    validate_no_rebase
    validate_branch
    validate_clean_tree
    capture!('git', '-C', canonical_project_path, 'fetch', 'origin')
    validate_ancestry

    {
      project_path: canonical_project_path,
      branch_name: branch_name,
      active_base_ref: active_base_ref,
      active_base_commit_sha: active_base_commit_sha,
      target_base_ref: target_base_ref,
      target_base_commit_sha: target_base_commit_sha,
      head_commit_sha: head_commit_sha,
      boundaries: boundaries,
      boundary_counts: boundary_counts,
      rewrites_commits: target_base_commit_sha != active_base_commit_sha
    }
  end

  private

  def validate_no_rebase
    return unless rebase_in_progress?

    raise 'A Git rebase is already in progress; run git rebase --abort before starting again'
  end

  def validate_branch
    current_branch = capture!('git', '-C', canonical_project_path, 'branch', '--show-current').strip
    return if current_branch == branch_name

    raise "Current branch #{current_branch} does not match configured branch #{branch_name}"
  end

  def validate_clean_tree
    status = capture!('git', '-C', canonical_project_path, 'status', '--porcelain')
    return if status.empty?

    raise "Working tree is not clean in #{canonical_project_path}:\n#{status}"
  end

  def validate_ancestry
    validate_ancestor(active_base_commit_sha)
    boundaries.each_value { |commit_sha| validate_ancestor(commit_sha) }
  end

  def validate_ancestor(commit_sha)
    capture!(
      'git', '-C', canonical_project_path,
      'merge-base', '--is-ancestor', commit_sha, head_commit_sha
    )
  end

  def boundary_counts
    @boundary_counts ||= boundaries.to_h do |name, commit_sha|
      count = capture!(
        'git', '-C', canonical_project_path, 'rev-list', '--count',
        "#{commit_sha}..#{head_commit_sha}"
      ).strip.to_i
      [name, count]
    end
  end

  def target_base_ref
    @target_base_ref ||= base_ref || active_base_ref
  end

  def target_base_commit_sha
    @target_base_commit_sha ||= capture!(
      'git', '-C', canonical_project_path, 'rev-parse', "#{target_base_ref}^{commit}"
    ).strip
  end

  def head_commit_sha
    @head_commit_sha ||= capture!('git', '-C', canonical_project_path, 'rev-parse', 'HEAD').strip
  end

  def rebase_in_progress?
    %w[rebase-merge rebase-apply].any? { |name| Dir.exist?(File.join(git_directory, name)) }
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
