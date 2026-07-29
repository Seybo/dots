# frozen_string_literal: true

class ReviewCommentUrl
  PATTERN = %r{\Ahttps://github\.com/(?<owner>[^/#]+)/(?<repo>[^/#]+)/pull/\d+#discussion_r(?<comment_id>\d+)\z}

  attr_reader :repository, :comment_id

  def initialize(value)
    match = PATTERN.match(value)
    raise ArgumentError, "Unsupported review comment URL: #{value.inspect}" if match.nil?

    @repository = "#{match[:owner]}/#{match[:repo]}"
    @comment_id = match[:comment_id]
  end
end
