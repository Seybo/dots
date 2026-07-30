# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe RenderIssue do
  let(:body) do
    <<~MARKDOWN.chomp
      **Avoid the extra query.**

      ```ruby
      records.to_a
      ```
    MARKDOWN
  end

  it 'renders GitHub metadata and the full Markdown body' do
    output = described_class.call(
      body: body,
      author: 'reviewer',
      path: 'app/services/example.rb',
      line: 42
    )

    expect(output).to eq(
      "Author: @reviewer\nPath: app/services/example.rb:42\n\n#{quoted_body}"
    )
  end

  it 'renders only the quoted local body' do
    expect(described_class.call(body: body)).to eq(quoted_body)
  end

  it 'reports an empty queue' do
    expect(described_class.call(body: nil)).to eq('No unresolved comments.')
  end

  def quoted_body
    body.lines(chomp: true).map { |line| line.empty? ? '>' : "> #{line}" }.join("\n")
  end
end
