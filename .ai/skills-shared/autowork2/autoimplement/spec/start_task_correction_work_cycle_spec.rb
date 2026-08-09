# frozen_string_literal: true

require_relative '../../spec/spec_helper'

RSpec.describe StartTaskCorrectionWorkCycle do
  let(:db) { Database.connection }
  let(:task_id) do
    db[:tasks].insert(
      created_at: Time.now,
      task_path: '/tasks/28',
      project_path: '/project',
      starting_commit_sha: 'starting-sha',
      state: 'initialized'
    )
  end

  before do
    allow(ValidateCleanGitState).to receive(:call).and_return('head-sha')
  end

  it 'batches approved issues from the exact review into one correction for the same step' do
    insert_implementation(step_number: 3, completed_at: Time.now)
    review_work_cycle_id = insert_review
    approved_issue_ids = [
      insert_produced_issue(review_work_cycle_id, body: 'First fix.', decision: 'approved'),
      insert_produced_issue(review_work_cycle_id, body: 'Second fix.', decision: 'approved'),
    ]
    insert_produced_issue(review_work_cycle_id, body: 'Skipped concern.', decision: 'skipped')

    work_cycle_id = described_class.call(
      task_id: task_id,
      review_work_cycle_id: review_work_cycle_id
    )

    expect(db[:work_cycles].where(id: work_cycle_id).first).to include(
      task_id: task_id,
      step_number: 3,
      role: 'worker',
      action: 'implementation',
      completed_at: nil
    )
    expect(db[:work_cycle_inputs].where(work_cycle_id: work_cycle_id).order(:id).
      select_map(:reported_issue_id)).to eq(approved_issue_ids)
    expect(TaskCorrectionNumber.call(work_cycle_id: work_cycle_id)).to eq(1)
    expect(ValidateCleanGitState).to have_received(:call).with(project_path: '/project')
  end

  it 'batches final-review issues into one whole-task correction' do
    db[:tasks].where(id: task_id).update(state: 'super_review')
    insert_implementation(step_number: 3, completed_at: Time.now)
    review_work_cycle_id = insert_review
    approved_issue_ids = [
      insert_produced_issue(review_work_cycle_id, body: 'Fix the cross-step flow.', decision: 'approved'),
      insert_produced_issue(review_work_cycle_id, body: 'Fix the final boundary.', decision: 'approved'),
    ]

    work_cycle_id = described_class.call(
      task_id: task_id,
      review_work_cycle_id: review_work_cycle_id
    )

    expect(db[:work_cycles].where(id: work_cycle_id).first).to include(
      task_id: task_id,
      step_number: nil,
      role: 'worker',
      action: 'implementation',
      completed_at: nil
    )
    expect(db[:work_cycle_inputs].where(work_cycle_id: work_cycle_id).order(:id).
      select_map(:reported_issue_id)).to eq(approved_issue_ids)
    expect(TaskCorrectionNumber.call(work_cycle_id: work_cycle_id)).to eq(1)
  end

  it 'uses whole-task corrections for every final-review Task state' do
    %w[super_review worker_final_review manager_review].each do |state|
      db[:tasks].where(id: task_id).update(state: state)
      insert_implementation(step_number: 3, completed_at: Time.now)
      review_work_cycle_id = insert_review
      insert_produced_issue(review_work_cycle_id, body: "Fix from #{state}.", decision: 'approved')

      work_cycle_id = described_class.call(
        task_id: task_id,
        review_work_cycle_id: review_work_cycle_id
      )

      expect(db[:work_cycles].where(id: work_cycle_id).get(:step_number)).to be_nil
      db[:work_cycles].where(id: work_cycle_id).update(completed_at: Time.now)
    end
  end

  it 'numbers a later correction from completed implementation history without persisting it' do
    insert_implementation(step_number: 3, completed_at: Time.now)
    first_review_id = insert_review
    insert_produced_issue(first_review_id, body: 'First fix.', decision: 'approved')
    first_correction_id = described_class.call(task_id: task_id, review_work_cycle_id: first_review_id)
    db[:work_cycles].where(id: first_correction_id).update(completed_at: Time.now)
    second_review_id = insert_review
    insert_produced_issue(second_review_id, body: 'Second fix.', decision: 'approved')

    second_correction_id = described_class.call(task_id: task_id, review_work_cycle_id: second_review_id)

    expect(db[:work_cycles].where(id: second_correction_id).get(:step_number)).to eq(3)
    expect(TaskCorrectionNumber.call(work_cycle_id: second_correction_id)).to eq(2)
    expect(db[:work_cycles].columns).not_to include(:correction_number)
  end

  it 'returns nil without checking Git when the review is clean or skipped-only' do
    insert_implementation(step_number: 3, completed_at: Time.now)
    clean_review_id = insert_review

    expect(
      described_class.call(task_id: task_id, review_work_cycle_id: clean_review_id)
    ).to be_nil

    skipped_review_id = insert_review
    insert_produced_issue(skipped_review_id, body: 'Skipped concern.', decision: 'skipped')

    expect(
      described_class.call(task_id: task_id, review_work_cycle_id: skipped_review_id)
    ).to be_nil
    expect(ValidateCleanGitState).not_to have_received(:call)
  end

  it 'does not dispatch an approved issue twice' do
    insert_implementation(step_number: 3, completed_at: Time.now)
    review_work_cycle_id = insert_review
    issue_id = insert_produced_issue(review_work_cycle_id, body: 'Fix once.', decision: 'approved')
    correction_id = insert_implementation(step_number: 3)
    db[:work_cycle_inputs].insert(
      created_at: Time.now,
      work_cycle_id: correction_id,
      reported_issue_id: issue_id
    )

    expect(
      described_class.call(task_id: task_id, review_work_cycle_id: review_work_cycle_id)
    ).to be_nil
    expect(ValidateCleanGitState).not_to have_received(:call)
  end

  it 'refuses correction while the review has an undecided issue' do
    insert_implementation(step_number: 3, completed_at: Time.now)
    review_work_cycle_id = insert_review
    insert_produced_issue(review_work_cycle_id, body: 'Needs a decision.', decision: nil)

    expect do
      described_class.call(task_id: task_id, review_work_cycle_id: review_work_cycle_id)
    end.to raise_error(RuntimeError, "Work Cycle #{review_work_cycle_id} has undecided Reported Issues")

    expect(ValidateCleanGitState).not_to have_received(:call)
  end

  it 'requires a positive step for an authored-step correction' do
    insert_implementation(step_number: nil, completed_at: Time.now)
    review_work_cycle_id = insert_review
    insert_produced_issue(review_work_cycle_id, body: 'Approved fix.', decision: 'approved')

    expect do
      described_class.call(task_id: task_id, review_work_cycle_id: review_work_cycle_id)
    end.to raise_error(
      RuntimeError,
      "Task #{task_id} latest authored-step implementation has no positive step number"
    )

    expect(ValidateCleanGitState).not_to have_received(:call)
  end

  it 'creates nothing when Git is dirty' do
    insert_implementation(step_number: 3, completed_at: Time.now)
    review_work_cycle_id = insert_review
    insert_produced_issue(review_work_cycle_id, body: 'Approved fix.', decision: 'approved')
    allow(ValidateCleanGitState).to receive(:call).and_raise('Working tree is not clean')
    original_work_cycle_count = db[:work_cycles].count

    expect do
      described_class.call(task_id: task_id, review_work_cycle_id: review_work_cycle_id)
    end.to raise_error(RuntimeError, 'Working tree is not clean')

    expect(db[:work_cycles].count).to eq(original_work_cycle_count)
  end

  def insert_implementation(step_number:, completed_at: nil)
    db[:work_cycles].insert(
      created_at: Time.now,
      completed_at: completed_at,
      task_id: task_id,
      step_number: step_number,
      role: 'worker',
      action: 'implementation'
    )
  end

  def insert_review
    db[:work_cycles].insert(
      created_at: Time.now,
      completed_at: Time.now,
      task_id: task_id,
      role: 'reviewer',
      action: 'review'
    )
  end

  def insert_produced_issue(work_cycle_id, body:, decision:)
    issue_id = StoreIssue.call(project_path: '/project', source: 'reviewer', body: body)
    db[:reported_issues].where(id: issue_id).update(decision: decision)
    db[:work_cycle_reported_issues].insert(
      created_at: Time.now,
      work_cycle_id: work_cycle_id,
      reported_issue_id: issue_id
    )
    issue_id
  end
end
