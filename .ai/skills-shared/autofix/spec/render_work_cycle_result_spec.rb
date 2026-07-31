# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe RenderWorkCycleResult do
  it 'renders an empty findings list' do
    expect(described_class.call(work_cycle_id: 2, findings: [])).
      to eq("Work Cycle 2 completed. Findings:\n- None")
  end

  it 'renders each finding' do
    expect(
      described_class.call(
        work_cycle_id: 2,
        findings: ['First finding.', 'Second finding.']
      )
    ).to eq("Work Cycle 2 completed. Findings:\n- First finding.\n- Second finding.")
  end
end
