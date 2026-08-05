# frozen_string_literal: true

require 'open3'

class InitializeTask
  include ServiceObject

  arguments :task_path

  def call
    return resume_task unless existing_task.nil?

    create_task
  end

  private

  def resume_task
    unless existing_task.fetch(:project_path) == project_path
      raise "Task #{existing_task.fetch(:id)} checkout mismatch: " \
            "expected #{existing_task.fetch(:project_path)}, got #{project_path}"
    end
    unless existing_task.fetch(:branch_name) == branch_name
      raise "Task #{existing_task.fetch(:id)} branch mismatch: " \
            "expected #{existing_task.fetch(:branch_name)}, got #{branch_name}"
    end

    existing_task
  end

  def create_task
    unless active_task.nil?
      raise "Task #{active_task.fetch(:id)} is already active for #{project_path}: " \
            "#{active_task.fetch(:task_path)}"
    end

    starting_commit_sha = ValidateCleanGitState.call(project_path: project_path)
    task_id = Database.connection.transaction(savepoint: true) do
      tasks.insert(
        created_at: Time.now,
        task_path: canonical_task_path,
        project_path: project_path,
        branch_name: branch_name,
        starting_commit_sha: starting_commit_sha,
        state: 'initialized'
      )
    end
    tasks.where(id: task_id).first
  end

  def existing_task
    @existing_task ||= tasks.where(task_path: canonical_task_path).first
  end

  def active_task
    @active_task ||= tasks.where(project_path: project_path).order(:id).first
  end

  def tasks
    Database.connection[:tasks]
  end

  def canonical_task_path
    @canonical_task_path ||= ValidateTaskFiles.call(task_path: task_path)
  end

  def project_path
    @project_path ||= File.realpath(ResolveProjectPath.call)
  end

  def branch_name
    @branch_name ||= capture!('git', '-C', project_path, 'branch', '--show-current').strip.tap do |branch|
      raise "Current checkout is detached in #{project_path}" if branch.empty?
    end
  end

  def capture!(*command)
    stdout, stderr, status = Open3.capture3(*command)
    return stdout if status.success?

    raise "#{command.join(' ')} failed with exit #{status.exitstatus}: #{stderr.strip}"
  end
end
