# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe RenderDecision do
  it 'renders the stored decision and reason followed by the next action' do
    output = described_class.call(
      decision: 'approved',
      reason: 'The write order loses data.',
      next_action: '> Fix the write order.'
    )

    expect(output).to eq(
      "Decision: approved\nReason: The write order loses data.\n\n> Fix the write order."
    )
  end
end
