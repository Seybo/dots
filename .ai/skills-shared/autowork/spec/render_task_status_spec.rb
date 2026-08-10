# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe 'RenderTaskStatus' do
  let(:service_class) { Object.const_get(:RenderTaskStatus) }

  it 'renders a Task folder whose workflows have not started' do
    expect(render_status(status(task: nil))).to eq(<<~TEXT.chomp)
      Task: 0038
      Task path: /tasks/env/0038-render-status
      Project: env
      Branch: main

      Autoimplement: not started
      Steps: 0/2 accepted

      Autofix: not started

      Next: /autoimplement
    TEXT
  end

  it 'renders active progress and one pending Work Cycle' do
    value = status(
      autoimplement: {
        state: 'initialized',
        accepted_step_count: 1,
        total_step_count: 2,
        pending: { type: 'work_cycle', id: 12 }
      },
      next_action: 'WaitWorkCycle 12'
    )

    expect(render_status(value)).to eq(<<~TEXT.chomp)
      Task: 0038
      Task path: /tasks/env/0038-render-status
      Project: env
      Branch: main

      Autoimplement:
      State: initialized
      Steps: 1/2 accepted
      Pending: Work Cycle 12

      Autofix: not started

      Next: WaitWorkCycle 12
    TEXT
  end

  it 'renders one pending Reported Issue' do
    value = status(
      autoimplement: {
        state: 'manager_review',
        accepted_step_count: 2,
        total_step_count: 2,
        pending: { type: 'issue', id: 7 }
      },
      next_action: 'Issue: 7'
    )

    expect(render_status(value)).to include("State: manager_review\nSteps: 2/2 accepted\nPending: Issue 7")
    expect(render_status(value)).to end_with('Next: Issue: 7')
  end

  it 'renders an active Autofix Review and its pending item' do
    value = status(
      autoimplement: status.fetch(:autoimplement).merge(
        state: 'final_checks_passed',
        accepted_step_count: 2
      ),
      autofix: {
        number: 3,
        source: 'local',
        state: 'reviewer_review',
        pending: { type: 'work_cycle', id: 18 }
      },
      next_action: 'WaitWorkCycle 18'
    )

    expect(render_status(value)).to include(<<~TEXT.chomp)
      Autofix:
      Review: 3
      Source: local
      State: reviewer_review
      Pending: Work Cycle 18
    TEXT
    expect(render_status(value)).to end_with('Next: WaitWorkCycle 18')
  end

  it 'renders only local completion for a completed Autofix Review' do
    value = status(
      autoimplement: status.fetch(:autoimplement).merge(state: 'final_checks_passed'),
      autofix: {
        number: 2,
        source: 'github',
        state: 'completed',
        pending: nil
      },
      next_action: 'None'
    )

    expect(render_status(value)).to include(<<~TEXT.chomp)
      Autofix:
      Review: 2
      Source: github
      State: completed
      Completion: local
    TEXT
    expect(render_status(value).scan(/^Review:/).length).to eq(1)
  end

  %w[super_review worker_final_review manager_review].each do |state|
    it "renders the #{state} lifecycle phase" do
      value = status(autoimplement: status.fetch(:autoimplement).merge(state: state))

      expect(render_status(value)).to include("State: #{state}")
      expect(render_status(value)).not_to include('Final checks: passed')
    end
  end

  it 'renders terminal final gates, local completion, and no push' do
    value = status(
      autoimplement: status.fetch(:autoimplement).merge(
        state: 'final_checks_passed',
        accepted_step_count: 2
      ),
      next_action: 'None'
    )

    expect(render_status(value)).to eq(<<~TEXT.chomp)
      Task: 0038
      Task path: /tasks/env/0038-render-status
      Project: env
      Branch: main

      Autoimplement:
      State: final_checks_passed
      Steps: 2/2 accepted
      Super-review: completed
      Final Worker review: completed
      Manager review: completed
      Final checks: passed
      Completion: local
      Push: not performed

      Autofix: not started

      Next: None
    TEXT
  end

  def render_status(value)
    service_class.call(status: value)
  end

  def status(overrides = {})
    {
      task_id: '0038',
      task_path: '/tasks/env/0038-render-status',
      project: 'env',
      branch: 'main',
      task: { id: 99 },
      autoimplement: {
        state: 'initialized',
        accepted_step_count: 0,
        total_step_count: 2,
        pending: nil
      },
      autofix: nil,
      next_action: '/autoimplement'
    }.merge(overrides)
  end
end
