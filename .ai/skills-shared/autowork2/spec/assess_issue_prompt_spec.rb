# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe 'Reported Issue assessment prompt' do
  let(:prompt) do
    File.read(File.expand_path('../app/prompts/assess_issue.md', __dir__))
  end

  it 'produces one factual self-contained reason for a durable decision' do
    expect(prompt).to include('one concise, factual, self-contained sentence')
    expect(prompt).to include('becomes the durable decision reason')
    expect(prompt).to include('Do not add a category, tag, score, or future prompt lesson')
  end
end
