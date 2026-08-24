# frozen_string_literal: true

require_relative '../../spec/spec_helper'

RSpec.describe StartTaskFinalWorkerReviewWorkCycle do
  let(:db) { Database.connection }
  let(:task_id) do
    db[:tasks].insert(
      created_at: Time.now,
      task_path: '/tasks/34',
      project_path: '/project',
      starting_commit_sha: 'starting-sha',
      state: 'worker_final_review',
      super_review_agent: 'claude'
    )
  end

  before do
    allow(ValidateCleanGitState).to receive(:call).and_return('head-sha')
  end

  it 'creates one whole-task Worker review Work Cycle' do
    work_cycle_id = described_class.call(task_id: task_id)

    expect(db[:work_cycles].where(id: work_cycle_id).first).to include(
      task_id: task_id,
      step_number: nil,
      role: 'worker',
      action: 'review',
      completed_at: nil
    )
    expect(db[:work_cycle_inputs].where(work_cycle_id: work_cycle_id).count).to eq(0)
    expect(ValidateCleanGitState).to have_received(:call).with(project_path: '/project')
  end

  it 'atomically transitions from super-review while creating the Worker review' do
    db[:tasks].where(id: task_id).update(state: 'super_review')

    work_cycle_id = described_class.call(task_id: task_id)

    expect(db[:tasks].where(id: task_id).get(:state)).to eq('worker_final_review')
    expect(db[:work_cycles].where(id: work_cycle_id).first).to include(
      role: 'worker',
      action: 'review'
    )
  end

  it 'transitions directly from initialized when super-review is disabled' do
    db[:tasks].where(id: task_id).update(state: 'initialized', super_review_agent: 'none')

    work_cycle_id = described_class.call(task_id: task_id)

    expect(db[:tasks].where(id: task_id).get(:state)).to eq('worker_final_review')
    expect(db[:work_cycles].where(id: work_cycle_id).first).to include(
      role: 'worker',
      action: 'review'
    )
  end

  it 'creates nothing and preserves super-review state when Git is dirty' do
    db[:tasks].where(id: task_id).update(state: 'super_review')
    allow(ValidateCleanGitState).to receive(:call).and_raise('Working tree is not clean')

    expect { described_class.call(task_id: task_id) }.
      to raise_error(RuntimeError, 'Working tree is not clean')

    expect(db[:tasks].where(id: task_id).get(:state)).to eq('super_review')
    expect(db[:work_cycles].count).to eq(0)
  end

  it 'does not create a second final Worker review Work Cycle' do
    described_class.call(task_id: task_id)

    expect { described_class.call(task_id: task_id) }.
      to raise_error(RuntimeError, "Task #{task_id} already has a final Worker review Work Cycle")

    expect(db[:work_cycles].count).to eq(1)
  end

  it 'preserves initialized state when direct final Worker review finds dirty Git' do
    db[:tasks].where(id: task_id).update(state: 'initialized', super_review_agent: 'none')
    allow(ValidateCleanGitState).to receive(:call).and_raise('Working tree is not clean')

    expect { described_class.call(task_id: task_id) }.
      to raise_error(RuntimeError, 'Working tree is not clean')

    expect(db[:tasks].where(id: task_id).get(:state)).to eq('initialized')
    expect(db[:work_cycles].count).to eq(0)
  end

  it 'requires a settled super-review unless the persisted agent is none' do
    db[:tasks].where(id: task_id).update(state: 'initialized')

    expect { described_class.call(task_id: task_id) }.
      to raise_error(
        RuntimeError,
        "Task #{task_id} cannot start final Worker review from state initialized"
      )

    expect(ValidateCleanGitState).not_to have_received(:call)
  end
end
