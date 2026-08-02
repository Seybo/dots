# frozen_string_literal: true

require 'json'

class WaitWorkCycle
  include ServiceObject

  REQUIRED_RESULT_FIELDS = %w[
    work_cycle_id
    role
    action
    status
    provider
    model
    reasoning_level
  ].freeze
  RESULT_STATUSES = %w[completed failed].freeze

  arguments :work_cycle_id

  def call
    sleep(1) until File.file?(result_path)
    validate_result
    raise_failed_result if work_cycle_result.fetch('status') == 'failed'

    return complete_implementation if work_cycle.fetch(:action) == 'implementation'

    complete_review
  end

  private

  def result_path
    "/tmp/autofix-work-cycle-#{work_cycle.fetch(:id)}.json"
  end

  def work_cycle_result
    @work_cycle_result ||= JSON.parse(File.read(result_path))
  end

  def work_cycle
    @work_cycle ||= Database.connection[:work_cycles].where(id: work_cycle_id).first
  end

  def validate_result
    REQUIRED_RESULT_FIELDS.each { |field| work_cycle_result.fetch(field) }
    expected_identity.each do |field, expected_value|
      next if work_cycle_result.fetch(field) == expected_value

      raise "Work Cycle result #{field} does not match Work Cycle #{work_cycle.fetch(:id)}"
    end
    status = work_cycle_result.fetch('status')
    raise "Unsupported Work Cycle result status: #{status}" unless RESULT_STATUSES.include?(status)
  end

  def expected_identity
    {
      'work_cycle_id' => work_cycle.fetch(:id),
      'role' => work_cycle.fetch(:role),
      'action' => work_cycle.fetch(:action)
    }
  end

  def raise_failed_result
    raise "Work Cycle #{work_cycle.fetch(:id)} failed: #{work_cycle_result.fetch('error')}"
  end

  def complete_implementation
    CommitWorkCycle.call(work_cycle_id: work_cycle.fetch(:id), work_cycle_result: work_cycle_result)
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
