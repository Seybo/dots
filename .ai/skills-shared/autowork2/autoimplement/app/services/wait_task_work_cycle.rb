# frozen_string_literal: true

class WaitTaskWorkCycle
  include ServiceObject

  arguments :work_cycle_id

  def call
    work_cycle_result
    return complete_implementation if work_cycle.fetch(:action) == 'implementation'

    complete_review
  end

  private

  def complete_implementation
    CommitWorkCycle.call(
      project_path: task.fetch(:project_path),
      message: commit_message
    )
    StoreTaskWorkCycleCompletion.call(
      work_cycle_id: work_cycle.fetch(:id),
      work_cycle_result: work_cycle_result
    )
    File.delete(result_path)
    output = "Worker implementation completed (Cycle #{work_cycle.fetch(:id)}, " \
             "Step #{work_cycle.fetch(:step_number)})."
    "#{output}\n#{ResumeTask.call(task_id: task.fetch(:id))}"
  end

  def complete_review
    ValidateCleanGitState.call(project_path: task.fetch(:project_path))
    output = RenderWorkCycleResult.call(
      work_cycle_id: work_cycle.fetch(:id),
      role: work_cycle.fetch(:role),
      action: work_cycle.fetch(:action),
      reported_issues: work_cycle_result.fetch('reported_issues')
    )
    StoreTaskWorkCycleCompletion.call(
      work_cycle_id: work_cycle.fetch(:id),
      work_cycle_result: work_cycle_result
    )
    File.delete(result_path)
    next_action = ResumeTask.call(task_id: task.fetch(:id))
    separator = next_action.start_with?('Issue:') ? "\n\n" : "\n"
    "#{output}#{separator}#{next_action}"
  end

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

  def commit_message
    return correction_commit_message if correction?

    title = task_step.fetch(:title)
    return "Step #{task_step.fetch(:number)}" if title.nil?

    "Step #{task_step.fetch(:number)}: #{title}"
  end

  def correction?
    Database.connection[:work_cycle_inputs].where(work_cycle_id: work_cycle.fetch(:id)).any?
  end

  def correction_commit_message
    correction_number = TaskCorrectionNumber.call(work_cycle_id: work_cycle.fetch(:id))
    "Step #{work_cycle.fetch(:step_number)} correction #{correction_number}"
  end

  def task_step
    @task_step ||= TaskSteps.new(task_path: task.fetch(:task_path)).find(work_cycle.fetch(:step_number))
  end
end
