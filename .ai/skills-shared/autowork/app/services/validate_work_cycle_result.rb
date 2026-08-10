# frozen_string_literal: true

require 'json'

class ValidateWorkCycleResult
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
    @result = JSON.parse(File.read(result_path))
    validate_required_fields
    validate_identity
    validate_status
    result
  end

  private

  attr_reader :result

  def validate_required_fields
    REQUIRED_FIELDS.each { |field| result.fetch(field) }
  end

  def validate_identity
    expected_identity.each do |field, expected_value|
      next if result.fetch(field) == expected_value

      raise "Work Cycle result #{field} does not match Work Cycle #{work_cycle.fetch(:id)}"
    end
  end

  def validate_status
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

  def work_cycle
    @work_cycle ||= Database.connection[:work_cycles].where(id: work_cycle_id).first
  end
end
