# frozen_string_literal: true

require 'open3'

class CompleteTaskRebase
  include ServiceObject

  arguments :preparation

  def call
    validate_git_state
    update_task
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

  def update_task
    validate_config
    Database.connection.transaction(savepoint: true) do
      updated_count = task_dataset.update(starting_commit_sha: new_starting_commit_sha)
      if updated_count != 1
        raise "Task #{task_id} metadata changed while its Git rebase was running"
      end

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

  def task_dataset
    Database.connection[:tasks].where(
      id: task_id,
      task_path: preparation.fetch(:task_path),
      project_path: project_path,
      starting_commit_sha: preparation.fetch(:starting_commit_sha),
      state: 'initialized'
    )
  end

  def render
    "Task #{task_id} rebased.\n" \
      "Active base: #{preparation.fetch(:active_base_ref)} @ " \
      "#{preparation.fetch(:active_base_commit_sha)} -> " \
      "#{preparation.fetch(:target_base_ref)} @ #{preparation.fetch(:target_base_commit_sha)}\n" \
      "Starting commit: #{preparation.fetch(:starting_commit_sha)} -> #{new_starting_commit_sha}\n" \
      'Push: not performed.'
  end

  def new_starting_commit_sha
    @new_starting_commit_sha ||= RemapGitBoundaries.call(
      preparation: preparation.fetch(:git_preparation)
    ).fetch(:task)
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
