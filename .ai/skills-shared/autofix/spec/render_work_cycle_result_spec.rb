# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe RenderWorkCycleResult do
  it 'renders an empty Reviewer findings list with the completed step name' do
    expect(
      described_class.call(
        work_cycle_id: 2,
        role: 'reviewer',
        action: 'review',
        findings: []
      )
    ).to eq("Reviewer review completed (Cycle 2). Findings:\n- None")
  end

  it 'renders each Worker finding with the completed step name' do
    expect(
      described_class.call(
        work_cycle_id: 3,
        role: 'worker',
        action: 'review',
        findings: ['First finding.', 'Second finding.']
      )
    ).to eq("Worker review completed (Cycle 3). Findings:\n- First finding.\n- Second finding.")
  end
end
