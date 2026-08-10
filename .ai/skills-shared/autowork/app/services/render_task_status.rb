# frozen_string_literal: true

class RenderTaskStatus
  include ServiceObject

  arguments :status

  def call
    lines = identity_lines
    lines << ''
    lines.concat(autoimplement_lines)
    lines << ''
    lines.concat(autofix_lines)
    lines << ''
    lines << "Next: #{status.fetch(:next_action)}"
    lines.join("\n")
  end

  private

  def identity_lines
    [
      "Task: #{status.fetch(:task_id)}",
      "Task path: #{status.fetch(:task_path)}",
      "Project: #{status.fetch(:project)}",
      "Branch: #{status.fetch(:branch)}",
    ]
  end

  def autoimplement_lines
    autoimplement = status.fetch(:autoimplement)
    lines = if status.fetch(:task).nil?
              ['Autoimplement: not started']
            else
              ['Autoimplement:', "State: #{autoimplement.fetch(:state)}"]
            end
    lines << "Steps: #{autoimplement.fetch(:accepted_step_count)}/" \
             "#{autoimplement.fetch(:total_step_count)} accepted"
    lines << pending_line(autoimplement.fetch(:pending)) unless autoimplement.fetch(:pending).nil?
    lines.concat(terminal_lines) if autoimplement.fetch(:state) == 'final_checks_passed'
    lines
  end

  def autofix_lines
    autofix = status.fetch(:autofix)
    return ['Autofix: not started'] if autofix.nil?

    lines = [
      'Autofix:',
      "Review: #{autofix.fetch(:number)}",
      "Source: #{autofix.fetch(:source)}",
      "State: #{autofix.fetch(:state)}",
    ]
    lines << pending_line(autofix.fetch(:pending)) unless autofix.fetch(:pending).nil?
    lines << 'Completion: local' if autofix.fetch(:state) == 'completed'
    lines
  end

  def pending_line(pending)
    case pending.fetch(:type)
    when 'work_cycle' then "Pending: Work Cycle #{pending.fetch(:id)}"
    when 'issue' then "Pending: Issue #{pending.fetch(:id)}"
    else raise "Unsupported pending item #{pending.fetch(:type)}"
    end
  end

  def terminal_lines
    [
      'Super-review: completed',
      'Final Worker review: completed',
      'Manager review: completed',
      'Final checks: passed',
      'Completion: local',
      'Push: not performed',
    ]
  end
end
