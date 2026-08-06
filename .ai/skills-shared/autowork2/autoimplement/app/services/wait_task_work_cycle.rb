# frozen_string_literal: true

class WaitTaskWorkCycle
  include ServiceObject

  arguments :work_cycle_id

  def call
    work_cycle_result
    CommitWorkCycle.call(
      project_path: task.fetch(:project_path),
      message: commit_message
    )
    store_completion
    File.delete(result_path)
    "Worker implementation completed (Cycle #{work_cycle.fetch(:id)}, " \
      "Step #{work_cycle.fetch(:step_number)})."
  end

  private

  def work_cycle_result
    @work_cycle_result ||= WaitWorkCycleResult.call(
      work_cycle_id: work_cycle.fetch(:id),
      result_path: result_path
    )
  end

  def result_path
    "/tmp/autoimplement-work-cycle-#{work_cycle.fetch(:id)}.json"
  end

  def work_cycle
    @work_cycle ||= Database.connection[:work_cycles].where(id: work_cycle_id).first
  end

  def task
    @task ||= Database.connection[:tasks].where(id: work_cycle.fetch(:task_id)).first
  end

  def task_step
    @task_step ||= TaskSteps.new(task_path: task.fetch(:task_path)).find(work_cycle.fetch(:step_number))
  end

  def commit_message
    title = task_step.fetch(:title)
    return "Step #{task_step.fetch(:number)}" if title.nil?

    "Step #{task_step.fetch(:number)}: #{title}"
  end

  def store_completion
    Database.connection[:work_cycles].where(id: work_cycle.fetch(:id)).update(
      completed_at: Time.now,
      provider: work_cycle_result.fetch('provider'),
      model: work_cycle_result.fetch('model'),
      reasoning_level: work_cycle_result.fetch('reasoning_level')
    )
  end
end
