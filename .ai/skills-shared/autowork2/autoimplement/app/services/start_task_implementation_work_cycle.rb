# frozen_string_literal: true

class StartTaskImplementationWorkCycle
  include ServiceObject

  arguments :task_id

  def call
    return if task_step.nil?

    ValidateCleanGitState.call(project_path: task.fetch(:project_path))
    Database.connection.transaction(savepoint: true) do
      work_cycles.insert(
        created_at: Time.now,
        completed_at: nil,
        review_id: nil,
        task_id: task.fetch(:id),
        step_number: task_step.fetch(:number),
        role: 'worker',
        action: 'implementation',
        provider: nil,
        model: nil,
        reasoning_level: nil
      )
    end
  end

  private

  def task_step
    @task_step ||= TaskSteps.new(task_path: task.fetch(:task_path)).all.find do |step|
      !accepted_step_numbers.include?(step.fetch(:number))
    end
  end

  def accepted_step_numbers
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

  def completed_work_cycles
    work_cycles.where(task_id: task.fetch(:id)).exclude(completed_at: nil).order(:id).all
  end

  def reviewer_accepted?(work_cycle_id)
    decisions = Database.connection[:reported_issues].
                join(:work_cycle_reported_issues, reported_issue_id: :id).
                where(Sequel[:work_cycle_reported_issues][:work_cycle_id] => work_cycle_id).
                select_map(Sequel[:reported_issues][:decision])
    decisions.all?('skipped')
  end

  def task
    @task ||= Database.connection[:tasks].where(id: task_id).first
  end

  def work_cycles
    Database.connection[:work_cycles]
  end
end
