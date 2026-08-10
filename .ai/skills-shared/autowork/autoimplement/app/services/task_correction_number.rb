# frozen_string_literal: true

class TaskCorrectionNumber
  include ServiceObject

  arguments :work_cycle_id

  def call
    count = previous_completed_implementation_count
    return count unless work_cycle.fetch(:step_number).nil?

    count + 1
  end

  private

  def previous_completed_implementation_count
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

  def work_cycle
    @work_cycle ||= Database.connection[:work_cycles].where(id: work_cycle_id).first
  end
end
