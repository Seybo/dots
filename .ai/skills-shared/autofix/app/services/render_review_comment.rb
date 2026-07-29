# frozen_string_literal: true

class RenderReviewComment
  include ServiceObject

  arguments :comment

  def call
    [author, location, '', quoted_body].join("\n")
  end

  private

  def author
    "Author: @#{comment.fetch('user').fetch('login')}"
  end

  def location
    "Path: #{comment.fetch('path')}:#{comment.fetch('line')}"
  end

  def quoted_body
    body.lines(chomp: true).map { |line| line.empty? ? '>' : "> #{line}" }.join("\n")
  end

  def body
    comment.fetch('body')
  end
end
