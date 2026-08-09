# frozen_string_literal: true

require_relative '../../spec/spec_helper'

RSpec.describe StartTaskManagerReviewWorkCycle do
  let(:db) { Database.connection }
  let(:task_id) do
    db[:tasks].insert(
      created_at: Time.now,
      task_path: '/tasks/35',
      project_path: '/project',
      starting_commit_sha: 'starting-sha',
      state: 'manager_review',
      super_review_agent: 'claude'
    )
  end

  before do
    allow(ValidateCleanGitState).to receive(:call).and_return('head-sha')
  end

  it 'creates one Manager review with every Task-reported issue in Work Cycle order' do
    first_review_id = insert_work_cycle(role: 'reviewer', action: 'review', completed_at: Time.now)
    first_issue_id = insert_issue(source: 'reviewer', body: 'First issue.', decision: 'approved')
    link_reported_issue(first_review_id, first_issue_id)
    second_review_id = insert_work_cycle(role: 'worker', action: 'review', completed_at: Time.now)
    second_issue_id = insert_issue(source: 'worker', body: 'Second issue.', decision: 'skipped')
    link_reported_issue(second_review_id, second_issue_id)
    third_review_id = insert_work_cycle(role: 'manager', action: 'review', completed_at: Time.now)
    third_issue_id = insert_issue(source: 'manager', body: 'Third issue.', decision: nil)
    link_reported_issue(third_review_id, third_issue_id)

    work_cycle_id = described_class.call(task_id: task_id)
    work_cycle = db[:work_cycles].where(id: work_cycle_id).first

    expect(work_cycle).to include(
      task_id: task_id,
      step_number: nil,
      role: 'manager',
      action: 'review',
      completed_at: nil
    )
    expect(db[:work_cycle_inputs].where(work_cycle_id: work_cycle_id).order(:id).
      select_map(:reported_issue_id)).to eq([first_issue_id, second_issue_id, third_issue_id])
    expect(ValidateCleanGitState).to have_received(:call).with(project_path: '/project')
  end

  it 'allows a fresh Manager review after the previous one completed' do
    insert_work_cycle(role: 'manager', action: 'review', completed_at: Time.now)

    work_cycle_id = described_class.call(task_id: task_id)

    expect(db[:work_cycles].where(id: work_cycle_id).first).to include(
      role: 'manager',
      action: 'review',
      completed_at: nil
    )
    expect(db[:work_cycles].where(task_id: task_id, role: 'manager', action: 'review').count).to eq(2)
  end

  it 'refuses a second incomplete Manager review without checking Git' do
    work_cycle_id = insert_work_cycle(role: 'manager', action: 'review')

    expect { described_class.call(task_id: task_id) }.
      to raise_error(RuntimeError, "Task #{task_id} already has incomplete Manager review #{work_cycle_id}")

    expect(ValidateCleanGitState).not_to have_received(:call)
    expect(db[:work_cycles].count).to eq(1)
  end

  it 'requires the pending Manager state without checking Git' do
    db[:tasks].where(id: task_id).update(state: 'worker_final_review')

    expect { described_class.call(task_id: task_id) }.
      to raise_error(RuntimeError, "Task #{task_id} cannot start Manager review from state worker_final_review")

    expect(ValidateCleanGitState).not_to have_received(:call)
    expect(db[:work_cycles].count).to eq(0)
  end

  it 'creates nothing when Git is dirty' do
    allow(ValidateCleanGitState).to receive(:call).and_raise('Working tree is not clean')

    expect { described_class.call(task_id: task_id) }.
      to raise_error(RuntimeError, 'Working tree is not clean')

    expect(db[:work_cycles].count).to eq(0)
  end

  it 'rolls back the Manager Work Cycle when input linking fails' do
    review_id = insert_work_cycle(role: 'reviewer', action: 'review', completed_at: Time.now)
    issue_id = insert_issue(source: 'reviewer', body: 'Issue.', decision: 'approved')
    link_reported_issue(review_id, issue_id)
    db.run(<<~SQL)
      CREATE TRIGGER fail_manager_input
      BEFORE INSERT ON work_cycle_inputs
      BEGIN
        SELECT RAISE(ABORT, 'input failed');
      END;
    SQL

    expect { described_class.call(task_id: task_id) }.
      to raise_error(Sequel::DatabaseError, /input failed/)

    expect(db[:work_cycles].where(task_id: task_id, role: 'manager', action: 'review').count).to eq(0)
  ensure
    db.run('DROP TRIGGER IF EXISTS fail_manager_input')
  end

  private

  def insert_work_cycle(role:, action:, completed_at: nil)
    db[:work_cycles].insert(
      created_at: Time.now,
      completed_at: completed_at,
      task_id: task_id,
      step_number: nil,
      role: role,
      action: action
    )
  end

  def insert_issue(source:, body:, decision:)
    issue_id = StoreIssue.call(project_path: '/project', source: source, body: body)
    db[:reported_issues].where(id: issue_id).update(decision: decision)
    issue_id
  end

  def link_reported_issue(work_cycle_id, issue_id)
    db[:work_cycle_reported_issues].insert(
      created_at: Time.now,
      work_cycle_id: work_cycle_id,
      reported_issue_id: issue_id
    )
  end
end
