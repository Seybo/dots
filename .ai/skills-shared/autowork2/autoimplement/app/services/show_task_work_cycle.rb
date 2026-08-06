# frozen_string_literal: true

require 'json'

class ShowTaskWorkCycle
  include ServiceObject

  arguments :work_cycle_id

  def call
    JSON.generate(
      work_cycle_id: work_cycle.fetch(:id),
      task_id: task.fetch(:id),
      role: work_cycle.fetch(:role),
      action: work_cycle.fetch(:action),
      task_path: task.fetch(:task_path),
      project_path: task.fetch(:project_path),
      branch_name: task.fetch(:branch_name),
      step_number: work_cycle.fetch(:step_number)
    )
  end

  private

  def work_cycle
    @work_cycle ||= Database.readonly_connection[:work_cycles].where(id: work_cycle_id).first
  end

  def task
    @task ||= Database.readonly_connection[:tasks].where(id: work_cycle.fetch(:task_id)).first
  end
end
