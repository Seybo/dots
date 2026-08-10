# frozen_string_literal: true

class AcceptedTaskStepNumbers
  include ServiceObject

  arguments :connection, :task_id

  def call
    current_step_number = nil
    completed_work_cycles.each_with_object([]) do |work_cycle, step_numbers|
      case [work_cycle.fetch(:role), work_cycle.fetch(:action)]
      when %w[worker implementation]
        current_step_number = work_cycle.fetch(:step_number)
        step_numbers.delete(current_step_number)
      when %w[reviewer review]
        step_numbers << current_step_number if reviewer_accepted?(work_cycle.fetch(:id))
      end
    end.uniq
  end

  private

  def completed_work_cycles
    connection[:work_cycles].
      where(task_id: task_id).
      exclude(completed_at: nil).
      order(:id).
      all
  end

  def reviewer_accepted?(work_cycle_id)
    decisions = connection[:reported_issues].
                join(:work_cycle_reported_issues, reported_issue_id: :id).
                where(Sequel[:work_cycle_reported_issues][:work_cycle_id] => work_cycle_id).
                select_map(Sequel[:reported_issues][:decision])
    decisions.all?('skipped')
  end
end
