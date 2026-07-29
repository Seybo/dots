# frozen_string_literal: true

require 'json'
require 'open3'

class FetchPullRequestComments
  include ServiceObject

  def call
    JSON.parse(capture!('gh', 'api', comments_endpoint))
  end

  private

  def comments_endpoint
    "repos/{owner}/{repo}/pulls/#{pull_request_number}/comments"
  end

  def pull_request_number
    @pull_request_number ||= JSON.parse(capture!('gh', 'pr', 'view', '--json', 'number')).fetch('number')
  end

  def capture!(*command)
    stdout, stderr, status = Open3.capture3(*command)
    return stdout if status.success?

    raise "#{command.join(' ')} failed with exit #{status.exitstatus}: #{stderr.strip}"
  end
end
