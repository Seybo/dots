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
  let(:issue) { { id: 12, body: body } }

  it 'renders the issue ID and quoted source-neutral body' do
    expect(described_class.call(issue: issue)).to eq("Issue: 12\n\n#{quoted_body}")
  end

  it 'reports an empty queue' do
    expect(described_class.call(issue: nil)).to eq('No unresolved issues.')
  end

  def quoted_body
    body.lines(chomp: true).map { |line| line.empty? ? '>' : "> #{line}" }.join("\n")
  end
end
