# frozen_string_literal: true

require 'rspec'
require_relative '../lib/markdown'

RSpec.describe Linear::Markdown do
  it 'extracts the title and removes only local routing metadata' do
    text = "Feature: [foo](../features/foo.md)\n\n# Story details\n\nName: Fix checkout\nPR:\n\n# Context\n\nBody\n"
    expect(described_class.parse(text)).to eq('title' => 'Fix checkout', 'description' => "# Context\n\nBody\n")
  end

  it 'keeps plain Markdown as description without inventing a title' do
    expect(described_class.parse("# Context\n\nBody\n")).to eq('description' => "# Context\n\nBody\n")
  end

  it 'strips Story details at the end without losing previous content' do
    expect(described_class.parse("# Context\n\nBody\n\n# Story details\nName: Fix\n"))
      .to eq('title' => 'Fix', 'description' => "# Context\n\nBody\n\n")
  end
end
