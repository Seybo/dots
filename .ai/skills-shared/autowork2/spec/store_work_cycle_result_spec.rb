# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe StoreWorkCycleResult do
  let(:db) { Database.connection }
  let(:task_id) do
    db[:tasks].insert(
      created_at: Time.now,
      task_path: '/tasks/28',
      project_path: '/project',
      branch_name: 'feature',
      starting_commit_sha: 'starting-sha',
      state: 'initialized'
    )
  end

  it 'stores implementation completion and provenance without Reported Issues' do
    work_cycle_id = insert_work_cycle(role: 'worker', action: 'implementation', step_number: 1)

    issue_ids = described_class.call(
      work_cycle_id: work_cycle_id,
      project_path: '/project',
      work_cycle_result: result(work_cycle_id, role: 'worker', action: 'implementation')
    )

    expect(issue_ids).to eq([])
    expect(db[:work_cycles].where(id: work_cycle_id).first).to include(
      completed_at: be_a(Time),
      provider: 'openai-codex',
      model: 'gpt-5.6-sol',
      reasoning_level: 'high'
    )
    expect(db[:reported_issues].count).to eq(0)
    expect(db[:work_cycle_reported_issues].count).to eq(0)
  end

  it 'atomically stores review completion and produced Reported Issues in result order' do
    work_cycle_id = insert_work_cycle(role: 'reviewer', action: 'review')
    work_cycle_result = result(work_cycle_id, role: 'reviewer', action: 'review').merge(
      'reported_issues' => ["First issue.\n", 'Second issue.']
    )

    issue_ids = described_class.call(
      work_cycle_id: work_cycle_id,
      project_path: '/project',
      work_cycle_result: work_cycle_result
    )

    issues = db[:reported_issues].order(:id).all
    expect(issue_ids).to eq(issues.map { |issue| issue.fetch(:id) })
    expect(issues).to match(
      [
        include(source: 'reviewer', source_id: nil, body: "First issue.\n", decision: nil),
        include(source: 'reviewer', source_id: nil, body: 'Second issue.', decision: nil),
      ]
    )
    expect(db[:work_cycle_reported_issues].order(:id).select_map(%i[work_cycle_id reported_issue_id])).
      to eq(issue_ids.map { |issue_id| [work_cycle_id, issue_id] })
  end

  it 'rolls back completion and Reported Issues when persistence fails' do
    work_cycle_id = insert_work_cycle(role: 'reviewer', action: 'review')
    work_cycle_result = result(work_cycle_id, role: 'reviewer', action: 'review').merge(
      'reported_issues' => ['Rolled back issue.', nil]
    )

    expect do
      described_class.call(
        work_cycle_id: work_cycle_id,
        project_path: '/project',
        work_cycle_result: work_cycle_result
      )
    end.to raise_error(Sequel::NotNullConstraintViolation)

    expect(db[:work_cycles].where(id: work_cycle_id).first).to include(
      completed_at: nil,
      provider: nil,
      model: nil,
      reasoning_level: nil
    )
    expect(db[:reported_issues].count).to eq(0)
    expect(db[:work_cycle_reported_issues].count).to eq(0)
  end

  def insert_work_cycle(role:, action:, step_number: nil)
    db[:work_cycles].insert(
      created_at: Time.now,
      task_id: task_id,
      step_number: step_number,
      role: role,
      action: action
    )
  end

  def result(work_cycle_id, role:, action:)
    {
      'work_cycle_id' => work_cycle_id,
      'role' => role,
      'action' => action,
      'status' => 'completed',
      'provider' => 'openai-codex',
      'model' => 'gpt-5.6-sol',
      'reasoning_level' => 'high'
    }
  end
end
