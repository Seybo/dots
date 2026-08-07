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
    commit_implementation
    store_completion
    remove_result
    output = "Worker implementation completed (Cycle #{work_cycle.fetch(:id)}, " \
             "Step #{work_cycle.fetch(:step_number)})."
    "#{output}\n#{ResumeTask.call(task_id: task.fetch(:id))}"
  end

  def commit_implementation
    CommitWorkCycle.call(
      project_path: task.fetch(:project_path),
      message: commit_message
    )
  rescue => err
    raise_boundary_error(
      'Git commit',
      err,
      'Resolve the Git problem, then use normal resume to reprocess the retained completed result; ' \
      'use ad-hoc Manager handling if it cannot safely continue.'
    )
  end

  def complete_review
    validate_review_git
    output = RenderWorkCycleResult.call(
      work_cycle_id: work_cycle.fetch(:id),
      role: work_cycle.fetch(:role),
      action: work_cycle.fetch(:action),
      reported_issues: review_reported_issues
    )
    store_completion
    remove_result
    next_action = ResumeTask.call(task_id: task.fetch(:id))
    separator = next_action.start_with?('Issue:') ? "\n\n" : "\n"
    "#{output}#{separator}#{next_action}"
  end

  def validate_review_git
    ValidateCleanGitState.call(project_path: task.fetch(:project_path))
  rescue => err
    raise_boundary_error(
      'Git review validation',
      err,
      'Discard the unexpected project changes, then use normal resume with the retained completed result.'
    )
  end

  def review_reported_issues
    work_cycle_result.fetch('reported_issues')
  rescue KeyError => err
    raise_participant_result_error(err)
  end

  def store_completion
    StoreTaskWorkCycleCompletion.call(
      work_cycle_id: work_cycle.fetch(:id),
      work_cycle_result: work_cycle_result
    )
  rescue => err
    raise_boundary_error(
      'database completion',
      err,
      'Keep the retained result and use ad-hoc Manager handling; do not retry the participant.'
    )
  end

  def remove_result
    File.delete(result_path)
  rescue => err
    raise_boundary_error(
      'transport cleanup',
      err,
      'The Work Cycle is already completed; use ad-hoc Manager handling for the stale transport and ' \
      'do not retry the participant.',
      path: result_path
    )
  end

  def work_cycle_result
    @work_cycle_result ||= WaitWorkCycleResult.call(
      work_cycle_id: work_cycle.fetch(:id),
      result_path: result_path
    )
  rescue => err
    raise_participant_result_error(err)
  end

  def raise_participant_result_error(error)
    raise_boundary_error(
      'participant result',
      error,
      'Discard all Git-reported changes from this attempt, confirm the participant stopped, then invoke ' \
      'Autoimplement with --retry.',
      path: result_path
    )
  end

  def raise_boundary_error(boundary, error, guidance, path: nil)
    location = path.nil? ? '' : " at #{path}"
    detail = error.message.to_s.lines.first.to_s.strip
    raise "Task #{task.fetch(:id)} Work Cycle #{work_cycle.fetch(:id)} #{boundary} failed#{location}: " \
          "#{detail}. #{guidance}"
  end

  def result_path
    @result_path ||= TaskWorkCycleResultPath.call(work_cycle_id: work_cycle.fetch(:id))
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
