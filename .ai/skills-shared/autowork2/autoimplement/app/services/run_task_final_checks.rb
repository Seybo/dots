# frozen_string_literal: true

class RunTaskFinalChecks
  include ServiceObject

  arguments :task_id

  def call
    result = RunFinalChecks.call(project_path: task.fetch(:project_path))
    return result.fetch(:output) unless result.fetch(:is_passing)

    ValidateCleanGitState.call(project_path: task.fetch(:project_path))
    store_transition
    "#{result.fetch(:output)}\nTask #{task.fetch(:id)} final checks passed."
  end

  private

  def task
    @task ||= Database.connection[:tasks].where(id: task_id).first
  end

  def store_transition
    Database.connection.transaction(savepoint: true) do
      Database.connection[:tasks].where(id: task.fetch(:id)).update(state: 'final_checks_passed')
    end
  end
end
