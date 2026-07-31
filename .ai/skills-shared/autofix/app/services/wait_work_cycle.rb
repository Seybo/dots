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

    output = complete_work_cycle
    File.delete(result_path)
    output
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

  def complete_work_cycle
    if work_cycle.fetch(:action) == 'implementation'
      commit_sha = CommitWorkCycle.call(work_cycle_id: work_cycle.fetch(:id), work_cycle_result: work_cycle_result)
      "Work Cycle #{work_cycle.fetch(:id)} completed at #{commit_sha}."
    else
      StoreWorkCycleCompletion.call(
        work_cycle_id: work_cycle.fetch(:id),
        work_cycle_result: work_cycle_result
      )
      "Work Cycle #{work_cycle.fetch(:id)} completed."
    end
  end
end
