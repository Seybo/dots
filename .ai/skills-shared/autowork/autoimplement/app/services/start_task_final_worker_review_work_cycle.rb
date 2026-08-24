# frozen_string_literal: true

class StartTaskFinalWorkerReviewWorkCycle
  include ServiceObject

  START_STATES = %w[super_review worker_final_review].freeze

  arguments :task_id

  def call
    ensure_start_state
    ensure_no_final_worker_review
    ValidateCleanGitState.call(project_path: task.fetch(:project_path))
    Database.connection.transaction(savepoint: true) do
      transition_task
      create_work_cycle
    end
  end

  private

  def ensure_start_state
    return if START_STATES.include?(task.fetch(:state))
    return if task.fetch(:state) == 'initialized' && task.fetch(:super_review_agent) == 'none'

    raise "Task #{task.fetch(:id)} cannot start final Worker review from state #{task.fetch(:state)}"
  end

  def ensure_no_final_worker_review
    return unless work_cycles.where(
      task_id: task.fetch(:id),
      role: 'worker',
      action: 'review'
    ).any?

    raise "Task #{task.fetch(:id)} already has a final Worker review Work Cycle"
  end

  def transition_task
    return if task.fetch(:state) == 'worker_final_review'

    starting_state = task.fetch(:state)
    updated_count = Database.connection[:tasks].
                    where(id: task.fetch(:id), state: starting_state).
                    update(state: 'worker_final_review')
    return if updated_count == 1

    raise "Task #{task.fetch(:id)} did not remain in #{starting_state} while starting final Worker review"
  end

  def create_work_cycle
    work_cycles.insert(
      created_at: Time.now,
      completed_at: nil,
      review_id: nil,
      task_id: task.fetch(:id),
      step_number: nil,
      role: 'worker',
      action: 'review',
      provider: nil,
      model: nil,
      reasoning_level: nil
    )
  end

  def task
    @task ||= Database.connection[:tasks].where(id: task_id).first
  end

  def work_cycles
    Database.connection[:work_cycles]
  end
end
