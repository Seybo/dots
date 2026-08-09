# frozen_string_literal: true

class RenderTask
  include ServiceObject

  arguments :task

  def call
    "Task: #{task.fetch(:id)}\n" \
      "Task path: #{task.fetch(:task_path)}\n" \
      "Project path: #{task.fetch(:project_path)}\n" \
      "Branch: #{branch_name}\n" \
      "Starting commit: #{task.fetch(:starting_commit_sha)}\n" \
      "State: #{task.fetch(:state)}\n" \
      "Super-review agent: #{task.fetch(:super_review_agent)}"
  end

  private

  def branch_name
    ReadTaskConfig.call(task_path: task.fetch(:task_path)).fetch('branch').fetch('name')
  end
end
