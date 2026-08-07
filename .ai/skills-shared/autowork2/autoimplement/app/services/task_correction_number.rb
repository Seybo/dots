# frozen_string_literal: true

class TaskCorrectionNumber
  include ServiceObject

  arguments :work_cycle_id

  def call
    current_work_cycle_id = work_cycle.fetch(:id)
    Database.connection[:work_cycles].
      where(
        task_id: work_cycle.fetch(:task_id),
        step_number: work_cycle.fetch(:step_number),
        role: 'worker',
        action: 'implementation'
      ).
      exclude(completed_at: nil).
      where { id < current_work_cycle_id }.
      count
  end

  private

  def work_cycle
    @work_cycle ||= Database.connection[:work_cycles].where(id: work_cycle_id).first
  end
end
