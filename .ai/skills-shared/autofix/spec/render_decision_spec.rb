# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe RenderDecision do
  it 'renders the stored decision followed by the next issue' do
    output = described_class.call(decision: 'approved', next_issue: '> Fix the write order.')

    expect(output).to eq("Decision: approved\n\n> Fix the write order.")
  end
end
