# frozen_string_literal: true

require 'open3'

class SquashTask
  include ServiceObject

  arguments :task_id, :project_path, :subject

  def call
    validate_task
    ValidateCleanGitState.call(project_path: project_path)
    validate_starting_commit
    final_commit_sha = SquashGitRange.call(
      project_path: project_path,
      parent_sha: task.fetch(:starting_commit_sha),
      subject: subject
    )
    "Task #{task.fetch(:id)} squashed locally.\n" \
      "Final commit: #{final_commit_sha} #{subject}\n" \
      'Push: not performed.'
  end

  private

  def validate_task
    raise ArgumentError, 'Squash subject cannot be empty' if subject.to_s.strip.empty?
    raise "Task #{task_id} was not found" if task.nil?
    raise "Task #{task.fetch(:id)} belongs to another project" unless same_project?
    raise "Task #{task.fetch(:id)} is not completed" unless task.fetch(:state) == 'final_checks_passed'

    validate_branch
  end

  def same_project?
    File.realpath(task.fetch(:project_path)) == File.realpath(project_path)
  end

  def validate_branch
    command = ['git', '-C', project_path, 'branch', '--show-current']
    stdout, stderr, status = Open3.capture3(*command)
    raise "#{command.join(' ')} failed with exit #{status.exitstatus}: #{stderr.strip}" unless status.success?

    current_branch = stdout.strip
    return if current_branch == task_context.fetch(:branch_name)

    raise "Task #{task.fetch(:id)} branch mismatch: expected #{task_context.fetch(:branch_name)}, " \
          "got #{current_branch}"
  end

  def validate_starting_commit
    command = [
      'git', '-C', project_path, 'merge-base', '--is-ancestor',
      task.fetch(:starting_commit_sha), 'HEAD'
    ]
    _stdout, stderr, status = Open3.capture3(*command)
    return if status.success?

    if status.exitstatus == 1
      raise "Task #{task.fetch(:id)} starting commit #{task.fetch(:starting_commit_sha)} " \
            'is not an ancestor of HEAD'
    end

    raise "#{command.join(' ')} failed with exit #{status.exitstatus}: #{stderr.strip}"
  end

  def task
    @task ||= Database.connection[:tasks].where(id: task_id).first
  end

  def task_context
    @task_context ||= LoadTaskContext.call(task: task)
  end
end
