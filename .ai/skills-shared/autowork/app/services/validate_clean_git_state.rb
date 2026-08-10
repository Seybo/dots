# frozen_string_literal: true

require 'open3'

class ValidateCleanGitState
  include ServiceObject

  arguments :project_path

  def call
    status = capture!('git', '-C', project_path, 'status', '--porcelain')
    unless status.empty?
      raise "Working tree is not clean in #{project_path}:\n#{status}"
    end

    capture!('git', '-C', project_path, 'rev-parse', 'HEAD').strip
  end

  private

  def capture!(*command)
    stdout, stderr, status = Open3.capture3(*command)
    return stdout if status.success?

    raise "#{command.join(' ')} failed with exit #{status.exitstatus}: #{stderr.strip}"
  end
end
