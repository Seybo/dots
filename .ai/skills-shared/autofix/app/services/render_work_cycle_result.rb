# frozen_string_literal: true

class RenderWorkCycleResult
  include ServiceObject

  arguments :work_cycle_id, :findings

  def call
    rendered_findings = findings.empty? ? ['None'] : findings
    lines = ["Work Cycle #{work_cycle_id} completed. Findings:"]
    lines.concat(rendered_findings.map { |finding| "- #{finding}" })
    lines.join("\n")
  end
end
