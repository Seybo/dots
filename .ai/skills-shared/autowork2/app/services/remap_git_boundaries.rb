# frozen_string_literal: true

require 'open3'

class RemapGitBoundaries
  include ServiceObject

  arguments :preparation

  def call
    return preparation.fetch(:boundaries) unless preparation.fetch(:rewrites_commits)

    preparation.fetch(:boundary_counts).transform_values do |count|
      capture!(
        'git', '-C', preparation.fetch(:project_path), 'rev-parse', "HEAD~#{count}^{commit}"
      ).strip
    end
  end

  private

  def capture!(*command)
    stdout, stderr, status = Open3.capture3(*command)
    return stdout if status.success?

    raise "#{command.join(' ')} failed with exit #{status.exitstatus}: #{stderr.strip}"
  end
end
