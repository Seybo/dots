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
  end

  def same_project?
    File.realpath(task.fetch(:project_path)) == File.realpath(project_path)
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
end
