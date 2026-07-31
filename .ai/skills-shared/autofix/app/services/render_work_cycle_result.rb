# frozen_string_literal: true

class RenderWorkCycleResult
  include ServiceObject

  arguments :work_cycle_id, :role, :action, :findings

  def call
    rendered_findings = findings.empty? ? ['None'] : findings
    lines = ["#{role.capitalize} #{action} completed (Cycle #{work_cycle_id}). Findings:"]
    lines.concat(rendered_findings.map { |finding| "- #{finding}" })
    lines.join("\n")
  end
end
