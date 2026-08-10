# frozen_string_literal: true

require 'open3'

class CompleteAutofixRebase
  include ServiceObject

  arguments :preparation

  def call
    validate_git_state
    update_metadata
    render
  end

  private

  def validate_git_state
    current_branch = capture!('git', '-C', project_path, 'branch', '--show-current').strip
    unless current_branch == preparation.fetch(:branch_name)
      raise "Current branch #{current_branch} does not match Task #{task_id} " \
            "branch #{preparation.fetch(:branch_name)}"
    end

    status = capture!('git', '-C', project_path, 'status', '--porcelain')
    return if status.empty?

    raise "Working tree is not clean after rebasing Task #{task_id}:\n#{status}"
  end

  def update_metadata
    validate_config
    Database.connection.transaction(savepoint: true) do
      validate_active_review
      update_task
      update_review unless preparation.fetch(:review_id).nil?
      UpdateTaskConfig.call(
        task_path: preparation.fetch(:task_path),
        active_base_ref: preparation.fetch(:target_base_ref),
        active_base_commit_sha: preparation.fetch(:target_base_commit_sha)
      )
    end
  end

  def validate_config
    branch = ReadTaskConfig.call(task_path: preparation.fetch(:task_path)).fetch('branch')
    expected = {
      'original_base_ref' => preparation.fetch(:original_base_ref),
      'original_base_commit_sha' => preparation.fetch(:original_base_commit_sha),
      'active_base_ref' => preparation.fetch(:active_base_ref),
      'active_base_commit_sha' => preparation.fetch(:active_base_commit_sha)
    }
    return if branch.slice(*expected.keys) == expected

    raise "Task #{task_id} config changed while its Git rebase was running"
  end

  def validate_active_review
    active_review_id = Database.connection[:reviews].
                       where(task_id: task_id, completed_at: nil).
                       order(:id).
                       get(:id)
    return if active_review_id == preparation.fetch(:review_id)

    raise "Task #{task_id} Review changed while its Git rebase was running"
  end

  def update_task
    updated_count = Database.connection[:tasks].where(
      id: task_id,
      task_path: preparation.fetch(:task_path),
      project_path: project_path,
      starting_commit_sha: preparation.fetch(:task_starting_commit_sha),
      state: 'final_checks_passed'
    ).update(starting_commit_sha: new_boundaries.fetch(:task))
    return if updated_count == 1

    raise "Task #{task_id} metadata changed while its Git rebase was running"
  end

  def update_review
    updated_count = Database.connection[:reviews].where(
      id: preparation.fetch(:review_id),
      task_id: task_id,
      completed_at: nil,
      starting_commit_sha: preparation.fetch(:review_starting_commit_sha)
    ).update(starting_commit_sha: new_boundaries.fetch(:review))
    return if updated_count == 1

    raise "Review #{preparation.fetch(:review_number)} metadata changed while its Git rebase was running"
  end

  def render
    lines = ["Task #{task_id} rebased."]
    lines << "Review: #{preparation.fetch(:review_number)}" unless preparation.fetch(:review_id).nil?
    lines << "Active base: #{preparation.fetch(:active_base_ref)} @ " \
             "#{preparation.fetch(:active_base_commit_sha)} -> " \
             "#{preparation.fetch(:target_base_ref)} @ #{preparation.fetch(:target_base_commit_sha)}"
    lines << "Task starting commit: #{preparation.fetch(:task_starting_commit_sha)} -> " \
             "#{new_boundaries.fetch(:task)}"
    unless preparation.fetch(:review_id).nil?
      lines << "Review starting commit: #{preparation.fetch(:review_starting_commit_sha)} -> " \
               "#{new_boundaries.fetch(:review)}"
    end
    lines << 'Push: not performed.'
    lines.join("\n")
  end

  def new_boundaries
    @new_boundaries ||= RemapGitBoundaries.call(preparation: preparation.fetch(:git_preparation))
  end

  def project_path
    preparation.fetch(:project_path)
  end

  def task_id
    preparation.fetch(:task_id)
  end

  def capture!(*command)
    stdout, stderr, status = Open3.capture3(*command)
    return stdout if status.success?

    raise "#{command.join(' ')} failed with exit #{status.exitstatus}: #{stderr.strip}"
  end
end
