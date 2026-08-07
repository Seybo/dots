# frozen_string_literal: true

class StoreTaskWorkCycleCompletion
  include ServiceObject

  arguments :work_cycle_id, :work_cycle_result

  def call
    StoreWorkCycleResult.call(
      work_cycle_id: work_cycle_id,
      project_path: task.fetch(:project_path),
      work_cycle_result: work_cycle_result
    )
  end

  private

  def work_cycle
    @work_cycle ||= Database.connection[:work_cycles].where(id: work_cycle_id).first
  end

  def task
    @task ||= Database.connection[:tasks].where(id: work_cycle.fetch(:task_id)).first
  end
end
