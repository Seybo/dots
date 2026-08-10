# frozen_string_literal: true

class ValidateProjectWorkflowAvailability
  include ServiceObject

  arguments :project_path, :workflow

  def call
    case workflow
    when 'autoimplement' then validate_no_active_review
    when 'autofix' then validate_no_active_task
    else raise ArgumentError, "Unsupported workflow #{workflow}"
    end
  end

  private

  def validate_no_active_review
    return if active_review.nil?

    raise "Review #{active_review.fetch(:id)} is already active for #{project_path}"
  end

  def validate_no_active_task
    return if active_task.nil?

    raise "Task #{active_task.fetch(:id)} is already active for #{project_path}: " \
          "#{active_task.fetch(:task_path)}"
  end

  def active_review
    @active_review ||= Database.connection[:reviews].
                       join(:tasks, id: :task_id).
                       where(Sequel[:tasks][:project_path] => project_path).
                       exclude(Sequel[:reviews][:state] => 'completed').
                       select_all(:reviews).
                       order(Sequel[:reviews][:id]).
                       first
  end

  def active_task
    @active_task ||= Database.connection[:tasks].
                     where(project_path: project_path).
                     exclude(state: 'final_checks_passed').
                     order(:id).
                     first
  end
end
