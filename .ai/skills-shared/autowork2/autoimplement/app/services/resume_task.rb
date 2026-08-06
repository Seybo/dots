# frozen_string_literal: true

class ResumeTask
  include ServiceObject

  arguments :task_id

  def call
    return "WaitWorkCycle #{incomplete_work_cycle.fetch(:id)}" unless incomplete_work_cycle.nil?

    work_cycle_id = StartTaskImplementationWorkCycle.call(task_id: task_id)
    return 'No unimplemented Task step.' if work_cycle_id.nil?

    "AutoImplementCycle #{work_cycle_id}"
  end

  private

  def incomplete_work_cycle
    @incomplete_work_cycle ||= Database.connection[:work_cycles].
                               where(
                                 task_id: task_id,
                                 role: 'worker',
                                 action: 'implementation',
                                 completed_at: nil
                               ).
                               order(:id).
                               last
  end
end
