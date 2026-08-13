# frozen_string_literal: true

class PrepareTaskRebase
  include ServiceObject

  REBASE_STATES = %w[initialized manager_review].freeze

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
      task_state: task.fetch(:state),
      is_manager_review_required: task.fetch(:is_manager_review_required),
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

    validate_task_state

    unless task.fetch(:project_path) == canonical_project_path
      raise "Task #{task.fetch(:id)} checkout mismatch: expected #{task.fetch(:project_path)}, " \
            "got #{canonical_project_path}"
    end
    if base_ref.nil? && branch.fetch('active_base_ref') == branch.fetch('active_base_commit_sha')
      raise "Task #{task.fetch(:id)} requires an explicit rebase target because its active base is a commit SHA"
    end
    return if incomplete_work_cycle.nil?

    raise "Task #{task.fetch(:id)} has incomplete Work Cycle #{incomplete_work_cycle.fetch(:id)}"
  end

  def validate_task_state
    state = task.fetch(:state)
    raise "Task #{task.fetch(:id)} cannot rebase from state #{state}" unless REBASE_STATES.include?(state)
    if task.fetch(:is_manager_review_required)
      raise "Task #{task.fetch(:id)} requires its post-rebase Manager review"
    end
    return if state == 'initialized' || manager_review_settled?

    raise "Task #{task.fetch(:id)} cannot rebase before final checks"
  end

  def manager_review_settled?
    latest = completed_work_cycles.last
    return false unless latest&.values_at(:role, :action) == %w[manager review]

    Database.connection[:reported_issues].
      join(:work_cycle_reported_issues, reported_issue_id: :id).
      where(Sequel[:work_cycle_reported_issues][:work_cycle_id] => latest.fetch(:id)).
      select_map(Sequel[:reported_issues][:decision]).all?('skipped')
  end

  def completed_work_cycles
    Database.connection[:work_cycles].
      where(task_id: task.fetch(:id)).
      exclude(completed_at: nil).
      order(:id)
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
