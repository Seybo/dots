# frozen_string_literal: true

require 'open3'

class ResolveProjectPath
  include ServiceObject

  def call
    stdout, stderr, status = Open3.capture3('git', 'rev-parse', '--show-toplevel')
    return File.realpath(stdout.strip) if status.success?

    raise "git rev-parse --show-toplevel failed with exit #{status.exitstatus}: #{stderr.strip}"
  end
end
