# frozen_string_literal: true

require 'open3'

class LoadCompletedTask
  include ServiceObject

  arguments :task_path, :project_path

  def call
    validate_task
    { task: task, config: config }
  end

  private

  def validate_task
    raise "No Autoimplement Task for #{canonical_task_path}" if task.nil?
    raise "Task #{task.fetch(:id)} is not completed" unless task.fetch(:state) == 'final_checks_passed'

    validate_project
    validate_current_branch
  end

  def validate_project
    return if task.fetch(:project_path) == canonical_project_path

    raise "Task #{task.fetch(:id)} checkout mismatch: expected #{task.fetch(:project_path)}, " \
          "got #{canonical_project_path}"
  end

  def validate_current_branch
    current_branch = capture!('git', '-C', canonical_project_path, 'branch', '--show-current').strip
    return if current_branch == configured_branch

    raise "Task #{task.fetch(:id)} branch mismatch: expected #{configured_branch}, got #{current_branch}"
  end

  def task
    @task ||= Database.connection[:tasks].where(task_path: canonical_task_path).first
  end

  def config
    @config ||= ReadTaskConfig.call(task_path: canonical_task_path)
  end

  def configured_branch
    @configured_branch ||= config.fetch('branch').fetch('name')
  end

  def canonical_task_path
    @canonical_task_path ||= ValidateTaskFiles.call(task_path: task_path)
  end

  def canonical_project_path
    @canonical_project_path ||= File.realpath(project_path)
  end

  def capture!(*command)
    stdout, stderr, status = Open3.capture3(*command)
    return stdout if status.success?

    raise "#{command.join(' ')} failed with exit #{status.exitstatus}: #{stderr.strip}"
  end
end
