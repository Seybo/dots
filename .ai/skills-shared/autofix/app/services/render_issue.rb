# frozen_string_literal: true

class RenderIssue
  include ServiceObject

  arguments :body, author: nil, path: nil, line: nil

  def call
    return 'No unresolved comments.' if body.nil?
    return quoted_body if author.nil?

    ["Author: @#{author}", "Path: #{path}:#{line}", '', quoted_body].join("\n")
  end

  private

  def quoted_body
    body.lines(chomp: true).map { |text| text.empty? ? '>' : "> #{text}" }.join("\n")
  end
end
