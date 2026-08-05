# frozen_string_literal: true

class ValidateTaskFiles
  include ServiceObject

  STEP_HEADING = /^## Step ([0-9]+)\b/

  arguments :task_path

  def call
    raise "Task path is not a directory: #{task_path}" unless File.directory?(canonical_task_path)

    validate_file('task.md')
    validate_file('steps.md')
    validate_steps
    canonical_task_path
  end

  private

  def canonical_task_path
    @canonical_task_path ||= File.realpath(task_path)
  rescue Errno::ENOENT
    raise "Task path does not exist: #{task_path}"
  end

  def validate_file(name)
    path = File.join(canonical_task_path, name)
    raise "Missing authored Task file: #{path}" unless File.file?(path)
  end

  def validate_steps
    path = File.join(canonical_task_path, 'steps.md')
    return if File.foreach(path).any? { |line| line.match?(STEP_HEADING) }

    raise "No canonical Step heading in #{path}"
  end
end
