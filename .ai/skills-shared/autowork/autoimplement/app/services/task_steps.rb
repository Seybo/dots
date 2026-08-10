# frozen_string_literal: true

class TaskSteps
  attr_reader :task_path

  def initialize(task_path:)
    @task_path = task_path
  end

  def all
    @all ||= File.foreach(steps_path).filter_map do |line|
      match = line.match(ValidateTaskFiles::STEP_HEADING)
      next if match.nil?

      {
        number: match[1].to_i,
        title: title(line, match)
      }
    end
  end

  def find(number)
    all.find { |step| step.fetch(:number) == number }
  end

  private

  def steps_path
    File.join(task_path, 'steps.md')
  end

  def title(line, match)
    value = line[match.end(0)..].strip.delete_prefix(':').strip
    value.empty? ? nil : value
  end
end
