# frozen_string_literal: true

class LoadTaskContext
  include ServiceObject

  arguments :task

  def call
    {
      task: task,
      config: config,
      project_path: task.fetch(:project_path),
      branch_name: branch.fetch('name')
    }
  end

  private

  def config
    @config ||= ReadTaskConfig.call(task_path: task.fetch(:task_path))
  end

  def branch
    @branch ||= config.fetch('branch')
  end
end
