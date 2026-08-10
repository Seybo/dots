# frozen_string_literal: true

require 'open3'

class CommitWorkCycle
  include ServiceObject

  arguments :project_path, :message

  def call
    capture!('git', '-C', project_path, 'add', '-A')
    capture!('git', '-C', project_path, 'commit', '-m', message)
  end

  private

  def capture!(*command)
    stdout, stderr, status = Open3.capture3(*command)
    return stdout if status.success?

    raise "#{command.join(' ')} failed with exit #{status.exitstatus}: #{stderr.strip}"
  end
end
