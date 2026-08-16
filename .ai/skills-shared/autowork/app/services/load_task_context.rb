# frozen_string_literal: true

class LoadTaskContext
  include ServiceObject

  FEATURE_REFERENCE = %r{\AFeature: \[(?<slug>[a-z][a-z0-9-]*)\]\(\.\./features/\k<slug>\.md\)\r?\n?\z}

  arguments :task

  def call
    {
      task: task,
      config: config,
      project_path: task.fetch(:project_path),
      branch_name: branch.fetch('name'),
      feature_path: feature_path,
      feature_text: feature_text
    }
  end

  private

  def feature_path
    return @feature_path if defined?(@feature_path)

    first_line = File.open(File.join(task.fetch(:task_path), 'task.md'), &:gets)
    match = FEATURE_REFERENCE.match(first_line.to_s)
    @feature_path = if match.nil?
                      nil
                    else
                      File.expand_path("../features/#{match[:slug]}.md", task.fetch(:task_path))
                    end
  end

  def feature_text
    File.read(feature_path) unless feature_path.nil?
  end

  def config
    @config ||= ReadTaskConfig.call(task_path: task.fetch(:task_path))
  end

  def branch
    @branch ||= config.fetch('branch')
  end
end
