# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe RenderIssue do
  it 'renders only the author, location, and full Markdown body in a quote block' do
    body = <<~MARKDOWN.chomp
      **Avoid the extra query.**

      ```ruby
      records.to_a
      ```
    MARKDOWN
    comment = {
      'id' => 456,
      'html_url' => 'https://github.com/example/project/pull/123#discussion_r456',
      'user' => { 'login' => 'reviewer' },
      'path' => 'app/services/example.rb',
      'line' => 42,
      'body' => body
    }

    quoted_body = body.lines(chomp: true).map { |line| line.empty? ? '>' : "> #{line}" }.join("\n")

    expect(described_class.call(comment: comment)).to eq(
      "Author: @reviewer\nPath: app/services/example.rb:42\n\n#{quoted_body}"
    )
  end

  it 'reports an empty queue' do
    expect(described_class.call(comment: nil)).to eq('No unresolved comments.')
  end
end
