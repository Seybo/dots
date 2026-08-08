# frozen_string_literal: true

require 'json'

class ShowTaskWorkCycle
  include ServiceObject

  arguments :work_cycle_id

  def call
    context = {
      work_cycle_id: work_cycle.fetch(:id),
      task_id: task.fetch(:id),
      role: work_cycle.fetch(:role),
      action: work_cycle.fetch(:action),
      task_path: task.fetch(:task_path),
      project_path: task.fetch(:project_path),
      branch_name: task.fetch(:branch_name),
      starting_commit_sha: task.fetch(:starting_commit_sha),
      super_review_agent: task.fetch(:super_review_agent),
      scope: scope,
      step_number: step_number,
      step_commit_count: step_commit_count,
      inputs: issues(:work_cycle_inputs),
      reported_issues: issues(:work_cycle_reported_issues)
    }
    context[:history] = history if manager_review?
    JSON.generate(context)
  end

  private

  def work_cycle
    @work_cycle ||= connection[:work_cycles].where(id: work_cycle_id).first
  end

  def task
    @task ||= connection[:tasks].where(id: work_cycle.fetch(:task_id)).first
  end

  def scope
    return 'manager_review' if manager_review?
    return work_cycle.fetch(:step_number).nil? ? 'whole_task_correction' : 'step_implementation' if implementation?
    return 'final_worker_review' if final_worker_review?

    return 'whole_task_correction_review' if latest_implementation_work_cycle.fetch(:step_number).nil?
    return 'super_review' if task.fetch(:state) == 'super_review'

    'step_review'
  end

  def implementation?
    work_cycle.fetch(:action) == 'implementation'
  end

  def final_worker_review?
    work_cycle.fetch(:role) == 'worker' && work_cycle.fetch(:action) == 'review'
  end

  def manager_review?
    work_cycle.fetch(:role) == 'manager' && work_cycle.fetch(:action) == 'review'
  end

  def step_number
    scopes_without_steps = %w[
      whole_task_correction whole_task_correction_review super_review final_worker_review manager_review
    ]
    return if scopes_without_steps.include?(scope)

    work_cycle.fetch(:step_number) || latest_implementation_work_cycle.fetch(:step_number)
  end

  def latest_implementation_work_cycle
    current_work_cycle_id = work_cycle.fetch(:id)
    @latest_implementation_work_cycle ||= connection[:work_cycles].
                                          where(
                                            task_id: task.fetch(:id),
                                            role: 'worker',
                                            action: 'implementation'
                                          ).
                                          exclude(completed_at: nil).
                                          where { id < current_work_cycle_id }.
                                          order(:id).
                                          last
  end

  def step_commit_count
    return if %w[whole_task_correction super_review final_worker_review manager_review].include?(scope)
    return 1 if scope == 'whole_task_correction_review'

    current_work_cycle_id = work_cycle.fetch(:id)
    completed_step_implementations.where { id < current_work_cycle_id }.count
  end

  def completed_step_implementations
    connection[:work_cycles].
      where(
        task_id: task.fetch(:id),
        step_number: step_number,
        role: 'worker',
        action: 'implementation'
      ).
      exclude(completed_at: nil)
  end

  def history
    connection[:work_cycles].where(task_id: task.fetch(:id)).order(:id).all.map do |item|
      {
        id: item.fetch(:id),
        role: item.fetch(:role),
        action: item.fetch(:action),
        step_number: item.fetch(:step_number),
        is_completed: !item.fetch(:completed_at).nil?,
        inputs: issues(:work_cycle_inputs, item.fetch(:id)),
        reported_issues: issues(:work_cycle_reported_issues, item.fetch(:id))
      }
    end
  end

  def issues(link_table, linked_work_cycle_id = work_cycle_id)
    connection[:reported_issues].
      join(link_table, reported_issue_id: :id).
      where(Sequel[link_table][:work_cycle_id] => linked_work_cycle_id).
      select_all(:reported_issues).
      order(Sequel[:reported_issues][:id]).
      all.
      map { |issue| issue.slice(:id, :source, :body, :decision) }
  end

  def connection
    Database.readonly_connection
  end
end
