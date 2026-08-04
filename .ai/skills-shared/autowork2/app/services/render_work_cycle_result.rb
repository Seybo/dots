# frozen_string_literal: true

class RenderWorkCycleResult
  include ServiceObject

  arguments :work_cycle_id, :role, :action, :reported_issues

  def call
    rendered_issues = reported_issues.empty? ? ['None'] : reported_issues
    lines = ["#{role.capitalize} #{action} completed (Cycle #{work_cycle_id}). Reported issues:"]
    lines.concat(rendered_issues.map { |reported_issue| "- #{reported_issue}" })
    lines.join("\n")
  end
end
