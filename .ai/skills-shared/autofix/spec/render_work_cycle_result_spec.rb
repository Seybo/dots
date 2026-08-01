# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe RenderWorkCycleResult do
  it 'renders an empty Reviewer issue list with the completed step name' do
    expect(
      described_class.call(
        work_cycle_id: 2,
        role: 'reviewer',
        action: 'review',
        reported_issues: []
      )
    ).to eq("Reviewer review completed (Cycle 2). Reported issues:\n- None")
  end

  it 'renders each Worker-reported issue with the completed step name' do
    expect(
      described_class.call(
        work_cycle_id: 3,
        role: 'worker',
        action: 'review',
        reported_issues: ['First issue.', 'Second issue.']
      )
    ).to eq("Worker review completed (Cycle 3). Reported issues:\n- First issue.\n- Second issue.")
  end
end
