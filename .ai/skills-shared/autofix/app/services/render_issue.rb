# frozen_string_literal: true

class RenderIssue
  include ServiceObject

  arguments :issue, author: nil, path: nil, line: nil

  def call
    return 'No unresolved issues.' if issue.nil?

    (metadata + ['', quoted_body]).join("\n")
  end

  private

  def metadata
    values = ["Issue: #{issue.fetch(:id)}"]
    values.push("Author: @#{author}", "Path: #{path}:#{line}") unless author.nil?
    values
  end

  def quoted_body
    issue.fetch(:body).lines(chomp: true).map { |text| text.empty? ? '>' : "> #{text}" }.join("\n")
  end
end
