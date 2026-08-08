# frozen_string_literal: true

require_relative '../../spec/spec_helper'

RSpec.describe StartTaskSuperReviewWorkCycle do
  let(:db) { Database.connection }
  let(:task_id) do
    db[:tasks].insert(
      created_at: Time.now,
      task_path: '/tasks/34',
      project_path: '/project',
      branch_name: 'feature',
      starting_commit_sha: 'starting-sha',
      state: 'initialized',
      super_review_agent: 'claude'
    )
  end

  before do
    allow(ValidateCleanGitState).to receive(:call).and_return('head-sha')
  end

  it 'atomically enters super-review and creates one whole-task Reviewer Work Cycle' do
    work_cycle_id = described_class.call(task_id: task_id)

    expect(db[:tasks].where(id: task_id).get(:state)).to eq('super_review')
    expect(db[:work_cycles].where(id: work_cycle_id).first).to include(
      task_id: task_id,
      step_number: nil,
      role: 'reviewer',
      action: 'review',
      completed_at: nil
    )
    expect(db[:work_cycle_inputs].where(work_cycle_id: work_cycle_id).count).to eq(0)
    expect(ValidateCleanGitState).to have_received(:call).with(project_path: '/project')
  end

  it 'creates nothing when Git is dirty' do
    allow(ValidateCleanGitState).to receive(:call).and_raise('Working tree is not clean')

    expect { described_class.call(task_id: task_id) }.
      to raise_error(RuntimeError, 'Working tree is not clean')

    expect(db[:tasks].where(id: task_id).get(:state)).to eq('initialized')
    expect(db[:work_cycles].count).to eq(0)
  end

  it 'does not create a second super-review Work Cycle' do
    described_class.call(task_id: task_id)

    expect { described_class.call(task_id: task_id) }.
      to raise_error(RuntimeError, "Task #{task_id} cannot start super-review from state super_review")

    expect(db[:work_cycles].count).to eq(1)
  end
end
