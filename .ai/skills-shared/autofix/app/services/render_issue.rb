# frozen_string_literal: true

class RenderIssue
  include ServiceObject

  arguments :issue

  def call
    return 'No unresolved issues.' if issue.nil?

    "Issue: #{issue.fetch(:id)}\n\n#{quoted_body}"
  end

  private

  def quoted_body
    issue.fetch(:body).lines(chomp: true).map { |text| text.empty? ? '>' : "> #{text}" }.join("\n")
  end
end
