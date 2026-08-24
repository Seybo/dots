# frozen_string_literal: true

require_relative '../../spec/spec_helper'

RSpec.describe StoreTaskWorkCycleCompletion do
  let(:db) { Database.connection }
  let(:task_id) do
    db[:tasks].insert(
      created_at: Time.now,
      task_path: '/tasks/28',
      project_path: '/project',
      starting_commit_sha: 'starting-sha',
      state: 'initialized',
      super_review_agent: 'claude'
    )
  end
  let(:work_cycle_id) do
    db[:work_cycles].insert(
      created_at: Time.now,
      task_id: task_id,
      role: 'reviewer',
      action: 'review'
    )
  end

  it 'atomically stores Reviewer completion, provenance, and Reported Issues in result order' do
    described_class.call(
      work_cycle_id: work_cycle_id,
      work_cycle_result: review_result(['First issue.', 'Second issue.'])
    )

    expect(db[:work_cycles].where(id: work_cycle_id).first).to include(
      completed_at: be_a(Time),
      provider: 'openai-codex',
      model: 'gpt-5.6-sol',
      reasoning_level: 'high'
    )
    issues = db[:reported_issues].order(:id).all
    expect(issues).to match(
      [
        include(source: 'reviewer', body: 'First issue.', decision: nil),
        include(source: 'reviewer', body: 'Second issue.', decision: nil),
      ]
    )
    expect(db[:work_cycle_reported_issues].order(:id).select_map(%i[work_cycle_id reported_issue_id])).
      to eq(issues.map { |issue| [work_cycle_id, issue.fetch(:id)] })
    expect(db[:tasks].where(id: task_id).get(:state)).to eq('initialized')
  end

  it 'stores a clean Reviewer pass without Reported Issues' do
    described_class.call(work_cycle_id: work_cycle_id, work_cycle_result: review_result([]))

    expect(db[:work_cycles].where(id: work_cycle_id).get(:completed_at)).to be_a(Time)
    expect(db[:reported_issues].count).to eq(0)
    expect(db[:work_cycle_reported_issues].count).to eq(0)
  end

  it 'rolls back completion and Reported Issues when persistence fails' do
    expect do
      described_class.call(
        work_cycle_id: work_cycle_id,
        work_cycle_result: review_result(['Rolled back issue.', nil])
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

  def review_result(reported_issues)
    {
      'work_cycle_id' => work_cycle_id,
      'role' => 'reviewer',
      'action' => 'review',
      'status' => 'completed',
      'provider' => 'openai-codex',
      'model' => 'gpt-5.6-sol',
      'reasoning_level' => 'high',
      'reported_issues' => reported_issues
    }
  end
end
