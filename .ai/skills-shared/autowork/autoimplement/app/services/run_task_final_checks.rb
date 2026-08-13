# frozen_string_literal: true

class RunTaskFinalChecks
  include ServiceObject

  arguments :task_id

  def call
    ensure_settled_manager_review
    result = RunFinalChecks.call(
      project_path: task.fetch(:project_path),
      starting_commit_sha: task.fetch(:starting_commit_sha)
    )
    return result.fetch(:output) unless result.fetch(:is_passing)

    ValidateCleanGitState.call(project_path: task.fetch(:project_path))
    store_transition
    "#{result.fetch(:output)}\nTask #{task.fetch(:id)} completed locally.\n" \
      "Push: not performed.\nAutoImplementSquash #{task.fetch(:id)}"
  end

  private

  def ensure_settled_manager_review
    unless task.fetch(:state) == 'manager_review'
      raise "Task #{task.fetch(:id)} cannot run final checks from state #{task.fetch(:state)}"
    end
    if task.fetch(:is_manager_review_required)
      raise "Task #{task.fetch(:id)} requires its post-rebase Manager review"
    end

    is_settled = !latest_manager_review.nil? &&
                 latest_manager_review == latest_completed_work_cycle &&
                 manager_decisions.all?('skipped')
    raise "Task #{task.fetch(:id)} latest Manager review is not settled" unless is_settled
  end

  def latest_manager_review
    @latest_manager_review ||= work_cycles.
                               where(task_id: task.fetch(:id), role: 'manager', action: 'review').
                               exclude(completed_at: nil).
                               order(:id).
                               last
  end

  def latest_completed_work_cycle
    @latest_completed_work_cycle ||= work_cycles.
                                     where(task_id: task.fetch(:id)).
                                     exclude(completed_at: nil).
                                     order(:id).
                                     last
  end

  def manager_decisions
    return [] if latest_manager_review.nil?

    Database.connection[:reported_issues].
      join(:work_cycle_reported_issues, reported_issue_id: :id).
      where(
        Sequel[:work_cycle_reported_issues][:work_cycle_id] => latest_manager_review.fetch(:id)
      ).
      select_map(Sequel[:reported_issues][:decision])
  end

  def task
    @task ||= Database.connection[:tasks].where(id: task_id).first
  end

  def work_cycles
    Database.connection[:work_cycles]
  end

  def store_transition
    Database.connection.transaction(savepoint: true) do
      updated_count = Database.connection[:tasks].
                      where(id: task.fetch(:id), state: 'manager_review').
                      update(state: 'final_checks_passed')
      raise "Task #{task.fetch(:id)} did not remain in Manager review" unless updated_count == 1
    end
  end
end
