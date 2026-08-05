# frozen_string_literal: true

class RenderTask
  include ServiceObject

  arguments :task

  def call
    "Task: #{task.fetch(:id)}\n" \
      "Task path: #{task.fetch(:task_path)}\n" \
      "Project path: #{task.fetch(:project_path)}\n" \
      "Branch: #{task.fetch(:branch_name)}\n" \
      "Starting commit: #{task.fetch(:starting_commit_sha)}\n" \
      "State: #{task.fetch(:state)}"
  end
end
