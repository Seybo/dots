# frozen_string_literal: true

require 'json'
require 'open3'

class FetchReviewComment
  include ServiceObject

  arguments :url

  def call
    JSON.parse(response)
  end

  private

  def response
    stdout, stderr, status = Open3.capture3('gh', 'api', endpoint)
    return stdout if status.success?

    raise "gh api failed with exit #{status.exitstatus}: #{stderr.strip}"
  end

  def endpoint
    "repos/#{review_comment_url.repository}/pulls/comments/#{review_comment_url.comment_id}"
  end

  def review_comment_url
    @review_comment_url ||= ReviewCommentUrl.new(url)
  end
end
