# frozen_string_literal: true

class WaitWorkCycle
  include ServiceObject

  arguments :work_cycle_id

  def call
    work_cycle_result
    return complete_implementation if work_cycle.fetch(:action) == 'implementation'

    complete_review
  end

  private

  def result_path
    "/tmp/autofix-work-cycle-#{work_cycle.fetch(:id)}.json"
  end

  def work_cycle_result
    @work_cycle_result ||= WaitWorkCycleResult.call(
      work_cycle_id: work_cycle.fetch(:id),
      result_path: result_path
    )
  end

  def work_cycle
    @work_cycle ||= Database.connection[:work_cycles].where(id: work_cycle_id).first
  end

  def complete_implementation
    CommitWorkCycle.call(
      project_path: review.fetch(:project_path),
      message: "Work cycle #{work_cycle.fetch(:id)}"
    )
    StoreWorkCycleCompletion.call(
      work_cycle_id: work_cycle.fetch(:id),
      work_cycle_result: work_cycle_result
    )
    File.delete(result_path)
    output = "Worker implementation completed (Cycle #{work_cycle.fetch(:id)})."
    next_action = ResumeReview.call(
      project_path: review.fetch(:project_path),
      branch_name: review.fetch(:branch_name)
    )
    "#{output}\n#{next_action}"
  end

  def complete_review
    output = RenderWorkCycleResult.call(
      work_cycle_id: work_cycle.fetch(:id),
      role: work_cycle.fetch(:role),
      action: work_cycle.fetch(:action),
      reported_issues: work_cycle_result.fetch('reported_issues')
    )
    StoreWorkCycleCompletion.call(
      work_cycle_id: work_cycle.fetch(:id),
      work_cycle_result: work_cycle_result
    )
    File.delete(result_path)

    case review.fetch(:state)
    when 'manager_issues_assessment' then "#{output}\n\n#{resume_review}"
    when 'worker_review', 'manager_review', 'manager_finalizing' then "#{output}\n#{resume_review}"
    else
      raise "Cannot continue Review #{review.fetch(:number)} from state #{review.fetch(:state)}"
    end
  end

  def resume_review
    ResumeReview.call(
      project_path: review.fetch(:project_path),
      branch_name: review.fetch(:branch_name)
    )
  end

  def review
    @review ||= Database.connection[:reviews].where(id: work_cycle.fetch(:review_id)).first
  end
end
