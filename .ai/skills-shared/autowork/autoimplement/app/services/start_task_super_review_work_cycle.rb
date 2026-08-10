# frozen_string_literal: true

class StartTaskSuperReviewWorkCycle
  include ServiceObject

  arguments :task_id

  def call
    ensure_initialized_task
    ValidateCleanGitState.call(project_path: task.fetch(:project_path))
    Database.connection.transaction(savepoint: true) do
      transition_task
      create_work_cycle
    end
  end

  private

  def ensure_initialized_task
    return if task.fetch(:state) == 'initialized'

    raise "Task #{task.fetch(:id)} cannot start super-review from state #{task.fetch(:state)}"
  end

  def transition_task
    updated_count = tasks.where(id: task.fetch(:id), state: 'initialized').update(state: 'super_review')
    return if updated_count == 1

    raise "Task #{task.fetch(:id)} did not remain initialized while starting super-review"
  end

  def create_work_cycle
    Database.connection[:work_cycles].insert(
      created_at: Time.now,
      completed_at: nil,
      review_id: nil,
      task_id: task.fetch(:id),
      step_number: nil,
      role: 'reviewer',
      action: 'review',
      provider: nil,
      model: nil,
      reasoning_level: nil
    )
  end

  def task
    @task ||= tasks.where(id: task_id).first
  end

  def tasks
    Database.connection[:tasks]
  end
end
