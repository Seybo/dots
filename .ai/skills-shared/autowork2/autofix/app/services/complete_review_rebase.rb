# frozen_string_literal: true

require 'open3'

class CompleteReviewRebase
  include ServiceObject

  arguments :preparation

  def call
    validate_git_state
    update_review
    render
  end

  private

  def validate_git_state
    current_branch = capture!('git', '-C', project_path, 'branch', '--show-current').strip
    unless current_branch == preparation.fetch(:branch_name)
      raise "Current branch #{current_branch} does not match Review #{review_number} " \
            "branch #{preparation.fetch(:branch_name)}"
    end

    status = capture!('git', '-C', project_path, 'status', '--porcelain')
    return if status.empty?

    raise "Working tree is not clean after rebasing Review #{review_number}:\n#{status}"
  end

  def update_review
    updated_count = Database.connection.transaction(savepoint: true) do
      review_dataset.update(
        starting_commit_sha: new_starting_commit_sha,
        active_base_ref: preparation.fetch(:target_base_ref),
        active_base_commit_sha: preparation.fetch(:target_base_commit_sha)
      )
    end
    return if updated_count == 1

    raise "Review #{review_number} metadata changed while its Git rebase was running"
  end

  def review_dataset
    Database.connection[:reviews].where(
      id: preparation.fetch(:review_id),
      completed_at: nil,
      project_path: project_path,
      branch_name: preparation.fetch(:branch_name),
      starting_commit_sha: preparation.fetch(:starting_commit_sha),
      original_base_ref: preparation.fetch(:original_base_ref),
      original_base_commit_sha: preparation.fetch(:original_base_commit_sha),
      active_base_ref: preparation.fetch(:active_base_ref),
      active_base_commit_sha: preparation.fetch(:active_base_commit_sha)
    )
  end

  def render
    "Review #{review_number} rebased.\n" \
      "Active base: #{preparation.fetch(:active_base_ref)} @ " \
      "#{preparation.fetch(:active_base_commit_sha)} -> " \
      "#{preparation.fetch(:target_base_ref)} @ #{preparation.fetch(:target_base_commit_sha)}\n" \
      "Starting commit: #{preparation.fetch(:starting_commit_sha)} -> #{new_starting_commit_sha}"
  end

  def new_starting_commit_sha
    @new_starting_commit_sha ||= capture!(
      'git', '-C', project_path, 'rev-parse',
      "HEAD~#{preparation.fetch(:commits_after_starting_count)}^{commit}"
    ).strip
  end

  def project_path
    preparation.fetch(:project_path)
  end

  def review_number
    preparation.fetch(:review_number)
  end

  def capture!(*command)
    stdout, stderr, status = Open3.capture3(*command)
    return stdout if status.success?

    raise "#{command.join(' ')} failed with exit #{status.exitstatus}: #{stderr.strip}"
  end
end
