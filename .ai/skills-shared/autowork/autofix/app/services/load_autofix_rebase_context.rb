# frozen_string_literal: true

class LoadAutofixRebaseContext
  include ServiceObject

  arguments :task_path, :project_path

  def call
    validate_task
    validate_review
    {
      task: task,
      task_path: canonical_task_path,
      project_path: canonical_project_path,
      config: task_context.fetch(:config),
      branch_name: task_context.fetch(:branch_name),
      review: review,
      boundaries: boundaries
    }
  end

  private

  def validate_task
    raise "No Autoimplement Task for #{canonical_task_path}" if task.nil?
    unless task.fetch(:state) == 'final_checks_passed'
      raise "Task #{task.fetch(:id)} cannot Autofix rebase from state #{task.fetch(:state)}"
    end

    unless task.fetch(:project_path) == canonical_project_path
      raise "Task #{task.fetch(:id)} checkout mismatch: expected #{task.fetch(:project_path)}, " \
            "got #{canonical_project_path}"
    end
    raise 'Local Tasks cannot be rebased' if local_task?
  end

  def validate_review
    return if incomplete_work_cycle.nil?

    raise "Review #{review.fetch(:number)} has incomplete Work Cycle #{incomplete_work_cycle.fetch(:id)}"
  end

  def local_task?
    %w[main master].include?(task_context.fetch(:branch_name)) &&
      branch.fetch('active_base_ref') == branch.fetch('active_base_commit_sha')
  end

  def boundaries
    values = { task: task.fetch(:starting_commit_sha) }
    values[:review] = review.fetch(:starting_commit_sha) unless review.nil?
    values
  end

  def incomplete_work_cycle
    return if review.nil?

    @incomplete_work_cycle ||= Database.connection[:work_cycles].
                               where(review_id: review.fetch(:id), completed_at: nil).
                               order(:id).
                               first
  end

  def review
    @review ||= Database.connection[:reviews].
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
    @canonical_task_path ||= File.realpath(task_path)
  end

  def canonical_project_path
    @canonical_project_path ||= File.realpath(project_path)
  end
end
