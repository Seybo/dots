# frozen_string_literal: true

class PrepareTaskRebase
  include ServiceObject

  arguments :task_path, :project_path, base_ref: nil

  def call
    validate_task
    git_preparation = PrepareGitRebase.call(
      project_path: canonical_project_path,
      branch_name: task_context.fetch(:branch_name),
      active_base_ref: branch.fetch('active_base_ref'),
      active_base_commit_sha: branch.fetch('active_base_commit_sha'),
      boundaries: { task: task.fetch(:starting_commit_sha) },
      base_ref: base_ref
    )
    {
      task_id: task.fetch(:id),
      task_path: canonical_task_path,
      project_path: canonical_project_path,
      branch_name: task_context.fetch(:branch_name),
      starting_commit_sha: task.fetch(:starting_commit_sha),
      original_base_ref: branch.fetch('original_base_ref'),
      original_base_commit_sha: branch.fetch('original_base_commit_sha'),
      active_base_ref: branch.fetch('active_base_ref'),
      active_base_commit_sha: branch.fetch('active_base_commit_sha'),
      target_base_ref: git_preparation.fetch(:target_base_ref),
      target_base_commit_sha: git_preparation.fetch(:target_base_commit_sha),
      git_preparation: git_preparation
    }
  end

  private

  def validate_task
    raise "No Autoimplement Task for #{canonical_task_path}" if task.nil?
    unless task.fetch(:state) == 'initialized'
      raise "Task #{task.fetch(:id)} cannot rebase from state #{task.fetch(:state)}"
    end

    unless task.fetch(:project_path) == canonical_project_path
      raise "Task #{task.fetch(:id)} checkout mismatch: expected #{task.fetch(:project_path)}, " \
            "got #{canonical_project_path}"
    end
    raise 'Local Tasks cannot be rebased' if local_task?
    return if incomplete_work_cycle.nil?

    raise "Task #{task.fetch(:id)} has incomplete Work Cycle #{incomplete_work_cycle.fetch(:id)}"
  end

  def local_task?
    %w[main master].include?(task_context.fetch(:branch_name)) &&
      branch.fetch('active_base_ref') == branch.fetch('active_base_commit_sha')
  end

  def incomplete_work_cycle
    @incomplete_work_cycle ||= Database.connection[:work_cycles].
                               where(task_id: task.fetch(:id), completed_at: nil).
                               order(:id).
                               first
  end

  def task
    @task ||= Database.connection[:tasks].where(task_path: canonical_task_path).first
  end

  def task_context
    @task_context ||= LoadTaskContext.call(task: task)
  end

  def branch
    @branch ||= task_context.fetch(:config).fetch('branch')
  end

  def canonical_task_path
    @canonical_task_path ||= ValidateTaskFiles.call(task_path: task_path)
  end

  def canonical_project_path
    @canonical_project_path ||= File.realpath(project_path)
  end
end
