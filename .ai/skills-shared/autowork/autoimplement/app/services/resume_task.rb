# frozen_string_literal: true

class ResumeTask
  include ServiceObject

  arguments :task_id

  def call
    return completed_output if task.fetch(:state) == 'final_checks_passed'
    return "WaitWorkCycle #{incomplete_work_cycle.fetch(:id)}" unless incomplete_work_cycle.nil?
    return resume_initialized if task.fetch(:state) == 'initialized'
    return resume_super_review if task.fetch(:state) == 'super_review'
    return resume_final_worker_review if task.fetch(:state) == 'worker_final_review'
    return resume_manager_review if task.fetch(:state) == 'manager_review'

    raise "Cannot resume Task #{task_id} from state #{task.fetch(:state)}"
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

  def resume_initialized
    return start_initial_implementation if latest_completed_work_cycle.nil?

    case [latest_completed_work_cycle.fetch(:role), latest_completed_work_cycle.fetch(:action)]
    when %w[worker implementation] then start_reviewer_review
    when %w[reviewer review] then resume_review_issues { continue_after_accepted_step }
    else
      raise "Cannot resume Task #{task_id} after " \
            "#{latest_completed_work_cycle.fetch(:role)}/#{latest_completed_work_cycle.fetch(:action)}"
    end
  end

  def resume_super_review
    if latest_completed_work_cycle.nil?
      raise "Task #{task_id} has no completed Work Cycle during super-review"
    end

    case [latest_completed_work_cycle.fetch(:role), latest_completed_work_cycle.fetch(:action)]
    when %w[worker implementation] then start_reviewer_review
    when %w[reviewer review] then resume_review_issues { start_final_worker_review }
    else
      raise "Cannot resume Task #{task_id} super-review after " \
            "#{latest_completed_work_cycle.fetch(:role)}/#{latest_completed_work_cycle.fetch(:action)}"
    end
  end

  def start_initial_implementation
    work_cycle_id = StartTaskImplementationWorkCycle.call(task_id: task_id)
    return 'No unimplemented Task step.' if work_cycle_id.nil?

    render_handoff(work_cycle_id)
  end

  def start_reviewer_review
    render_handoff(StartTaskReviewerReviewWorkCycle.call(task_id: task_id))
  end

  def resume_final_worker_review
    return start_final_worker_review unless final_worker_review_exists?

    if latest_completed_work_cycle.nil?
      raise "Task #{task_id} has no completed Work Cycle during final Worker review"
    end

    case [latest_completed_work_cycle.fetch(:role), latest_completed_work_cycle.fetch(:action)]
    when %w[worker implementation] then start_reviewer_review
    when %w[worker review], %w[reviewer review]
      resume_review_issues { transition_to_manager_review }
    else
      raise "Cannot resume Task #{task_id} final Worker review after " \
            "#{latest_completed_work_cycle.fetch(:role)}/#{latest_completed_work_cycle.fetch(:action)}"
    end
  end

  def resume_review_issues
    issue = FindNextTaskIssue.call(review_work_cycle_id: latest_completed_work_cycle.fetch(:id))
    return RenderIssue.call(issue: issue) unless issue.nil?

    work_cycle_id = StartTaskCorrectionWorkCycle.call(
      task_id: task_id,
      review_work_cycle_id: latest_completed_work_cycle.fetch(:id)
    )
    return render_handoff(work_cycle_id) unless work_cycle_id.nil?

    yield
  end

  def start_final_worker_review
    work_cycle_id = StartTaskFinalWorkerReviewWorkCycle.call(task_id: task_id)
    render_handoff(work_cycle_id)
  end

  def final_worker_review_exists?
    work_cycles.where(task_id: task_id, role: 'worker', action: 'review').any?
  end

  def transition_to_manager_review
    Database.connection.transaction(savepoint: true) do
      updated_count = Database.connection[:tasks].
                      where(id: task.fetch(:id), state: 'worker_final_review').
                      update(state: 'manager_review')
      raise "Task #{task_id} did not remain in final Worker review" unless updated_count == 1
    end
    start_manager_review
  end

  def resume_manager_review
    return start_post_rebase_manager_review if task.fetch(:is_manager_review_required)
    return start_manager_review unless manager_review_exists?

    case [latest_completed_work_cycle.fetch(:role), latest_completed_work_cycle.fetch(:action)]
    when %w[worker implementation] then start_reviewer_review
    when %w[manager review]
      resume_review_issues { RunTaskFinalChecks.call(task_id: task.fetch(:id)) }
    when %w[reviewer review]
      resume_review_issues { start_manager_review }
    else
      raise "Cannot resume Task #{task_id} Manager review after " \
            "#{latest_completed_work_cycle.fetch(:role)}/#{latest_completed_work_cycle.fetch(:action)}"
    end
  end

  def start_manager_review
    render_handoff(StartTaskManagerReviewWorkCycle.call(task_id: task.fetch(:id)))
  end

  def start_post_rebase_manager_review
    work_cycle_id = nil
    Database.connection.transaction(savepoint: true) do
      work_cycle_id = StartTaskManagerReviewWorkCycle.call(task_id: task.fetch(:id))
      updated_count = Database.connection[:tasks].
                      where(
                        id: task.fetch(:id),
                        state: 'manager_review',
                        is_manager_review_required: true
                      ).
                      update(is_manager_review_required: false)
      raise "Task #{task_id} did not retain its post-rebase Manager review requirement" unless updated_count == 1
    end
    render_handoff(work_cycle_id)
  end

  def manager_review_exists?
    work_cycles.where(task_id: task_id, role: 'manager', action: 'review').any?
  end

  def completed_output
    "Task #{task.fetch(:id)} completed locally.\nPush: not performed."
  end

  def continue_after_accepted_step
    step_number = latest_implementation_work_cycle.fetch(:step_number)
    work_cycle_id = StartTaskImplementationWorkCycle.call(task_id: task_id)
    work_cycle_id ||= StartTaskSuperReviewWorkCycle.call(task_id: task.fetch(:id))
    "Step #{step_number} accepted.\n#{render_handoff(work_cycle_id)}"
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

  def task
    @task ||= Database.connection[:tasks].where(id: task_id).first
  end

  def work_cycles
    Database.connection[:work_cycles]
  end
end
