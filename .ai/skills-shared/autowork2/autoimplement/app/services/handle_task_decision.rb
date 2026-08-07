# frozen_string_literal: true

class HandleTaskDecision
  include ServiceObject

  arguments :issue_id, :decision

  def call
    StoreDecision.call(issue_id: issue_id, decision: decision)
    RenderDecision.call(
      decision: decision,
      next_action: ResumeTask.call(task_id: work_cycle.fetch(:task_id))
    )
  end

  private

  def work_cycle
    @work_cycle ||= begin
      work_cycle_id = Database.connection[:work_cycle_reported_issues].
                      where(reported_issue_id: issue_id).
                      get(:work_cycle_id)
      Database.connection[:work_cycles].where(id: work_cycle_id).first
    end
  end
end
