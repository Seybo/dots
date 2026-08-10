# frozen_string_literal: true

class StartTaskImplementationWorkCycle
  include ServiceObject

  arguments :task_id

  def call
    return if task_step.nil?

    ValidateCleanGitState.call(project_path: task.fetch(:project_path))
    Database.connection.transaction(savepoint: true) do
      work_cycles.insert(
        created_at: Time.now,
        completed_at: nil,
        review_id: nil,
        task_id: task.fetch(:id),
        step_number: task_step.fetch(:number),
        role: 'worker',
        action: 'implementation',
        provider: nil,
        model: nil,
        reasoning_level: nil
      )
    end
  end

  private

  def task_step
    @task_step ||= TaskSteps.new(task_path: task.fetch(:task_path)).all.find do |step|
      !accepted_step_numbers.include?(step.fetch(:number))
    end
  end

  def accepted_step_numbers
    AcceptedTaskStepNumbers.call(connection: Database.connection, task_id: task.fetch(:id))
  end

  def task
    @task ||= Database.connection[:tasks].where(id: task_id).first
  end

  def work_cycles
    Database.connection[:work_cycles]
  end
end
