# frozen_string_literal: true

class ResumeTask
  include ServiceObject

  arguments :task_id

  def call
    return "WaitWorkCycle #{incomplete_work_cycle.fetch(:id)}" unless incomplete_work_cycle.nil?
    return start_initial_implementation if latest_completed_work_cycle.nil?

    case [latest_completed_work_cycle.fetch(:role), latest_completed_work_cycle.fetch(:action)]
    when %w[worker implementation] then start_reviewer_review
    when %w[reviewer review] then resume_reviewer_issues
    else
      raise "Cannot resume Task #{task_id} after " \
            "#{latest_completed_work_cycle.fetch(:role)}/#{latest_completed_work_cycle.fetch(:action)}"
    end
  end

  private

  def incomplete_work_cycle
    @incomplete_work_cycle ||= work_cycles.where(task_id: task_id, completed_at: nil).order(:id).last
  end

  def latest_completed_work_cycle
    @latest_completed_work_cycle ||= work_cycles.
                                     where(task_id: task_id).
                                     exclude(completed_at: nil).
                                     order(:id).
                                     last
  end

  def start_initial_implementation
    work_cycle_id = StartTaskImplementationWorkCycle.call(task_id: task_id)
    return 'No unimplemented Task step.' if work_cycle_id.nil?

    render_handoff(work_cycle_id)
  end

  def start_reviewer_review
    render_handoff(StartTaskReviewerReviewWorkCycle.call(task_id: task_id))
  end

  def resume_reviewer_issues
    issue = FindNextTaskIssue.call(review_work_cycle_id: latest_completed_work_cycle.fetch(:id))
    return RenderIssue.call(issue: issue) unless issue.nil?

    work_cycle_id = StartTaskCorrectionWorkCycle.call(
      task_id: task_id,
      review_work_cycle_id: latest_completed_work_cycle.fetch(:id)
    )
    return render_handoff(work_cycle_id) unless work_cycle_id.nil?

    continue_after_accepted_step
  end

  def continue_after_accepted_step
    step_number = latest_implementation_work_cycle.fetch(:step_number)
    work_cycle_id = StartTaskImplementationWorkCycle.call(task_id: task_id)
    next_action = work_cycle_id.nil? ? 'No unimplemented Task step.' : render_handoff(work_cycle_id)
    "Step #{step_number} accepted.\n#{next_action}"
  end

  def latest_implementation_work_cycle
    current_work_cycle_id = latest_completed_work_cycle.fetch(:id)
    @latest_implementation_work_cycle ||= work_cycles.
                                          where(
                                            task_id: task_id,
                                            role: 'worker',
                                            action: 'implementation'
                                          ).
                                          exclude(completed_at: nil).
                                          where { id < current_work_cycle_id }.
                                          order(:id).
                                          last
  end

  def render_handoff(work_cycle_id)
    "AutoImplementCycle #{work_cycle_id}"
  end

  def work_cycles
    Database.connection[:work_cycles]
  end
end
