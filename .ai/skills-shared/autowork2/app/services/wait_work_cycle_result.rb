# frozen_string_literal: true

require 'json'

class WaitWorkCycleResult
  include ServiceObject

  REQUIRED_FIELDS = %w[
    work_cycle_id
    role
    action
    status
    provider
    model
    reasoning_level
  ].freeze
  STATUSES = %w[completed failed].freeze

  arguments :work_cycle_id, :result_path

  def call
    sleep(1) until File.file?(result_path)
    validate_result
    raise_failed_result if result.fetch('status') == 'failed'

    result
  end

  private

  def result
    @result ||= JSON.parse(File.read(result_path))
  end

  def work_cycle
    @work_cycle ||= Database.connection[:work_cycles].where(id: work_cycle_id).first
  end

  def validate_result
    REQUIRED_FIELDS.each { |field| result.fetch(field) }
    expected_identity.each do |field, expected_value|
      next if result.fetch(field) == expected_value

      raise "Work Cycle result #{field} does not match Work Cycle #{work_cycle.fetch(:id)}"
    end
    status = result.fetch('status')
    raise "Unsupported Work Cycle result status: #{status}" unless STATUSES.include?(status)
  end

  def expected_identity
    {
      'work_cycle_id' => work_cycle.fetch(:id),
      'role' => work_cycle.fetch(:role),
      'action' => work_cycle.fetch(:action)
    }
  end

  def raise_failed_result
    raise "Work Cycle #{work_cycle.fetch(:id)} failed: #{result.fetch('error')}"
  end
end
