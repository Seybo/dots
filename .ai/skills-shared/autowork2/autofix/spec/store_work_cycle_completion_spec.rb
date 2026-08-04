# frozen_string_literal: true

require 'json'
require_relative '../../spec/spec_helper'

RSpec.describe StoreWorkCycleCompletion do
  let(:db) { Database.connection }

  it 'atomically stores Reviewer-reported issues and their relationships in result order' do
    review_id = insert_review(state: 'reviewer_review')
    work_cycle_id = insert_work_cycle(review_id: review_id, role: 'reviewer')
    result = review_result(
      work_cycle_id,
      role: 'reviewer',
      reported_issues: ["First reported issue.\n", 'Second reported issue.']
    )

    described_class.call(work_cycle_id: work_cycle_id, work_cycle_result: result)

    expect(db[:work_cycles].where(id: work_cycle_id).first).to include(
      completed_at: be_a(Time),
      provider: 'openai-codex',
      model: 'gpt-5.6-sol',
      reasoning_level: 'high'
    )
    expect(db[:reviews].where(id: review_id).get(:state)).to eq('manager_issues_assessment')
    reported_issues = db[:reported_issues].order(:id).all
    expect(reported_issues).to match(
      [
        include(source: 'reviewer', source_id: nil, body: "First reported issue.\n", decision: nil),
        include(source: 'reviewer', source_id: nil, body: 'Second reported issue.', decision: nil),
      ]
    )
    expect(db[:review_issues].order(:id).select_map(%i[review_id reported_issue_id])).to eq(
      reported_issues.map { |reported_issue| [review_id, reported_issue.fetch(:id)] }
    )
    expect(db[:work_cycle_reported_issues].order(:id).select_map(%i[work_cycle_id reported_issue_id])).
      to eq(reported_issues.map { |reported_issue| [work_cycle_id, reported_issue.fetch(:id)] })
  end

  it 'stores final Worker-reported issues with the Worker source' do
    review_id = insert_review(state: 'worker_review')
    work_cycle_id = insert_work_cycle(review_id: review_id, role: 'worker')
    result = review_result(work_cycle_id, role: 'worker', reported_issues: ['Worker-reported issue.'])

    described_class.call(work_cycle_id: work_cycle_id, work_cycle_result: result)

    reported_issue = db[:reported_issues].first
    expect(reported_issue).
      to include(source: 'worker', source_id: nil, body: 'Worker-reported issue.', decision: nil)
    expect(db[:reviews].where(id: review_id).get(:state)).to eq('manager_issues_assessment')
    expect(db[:review_issues].get(:reported_issue_id)).to eq(reported_issue.fetch(:id))
    expect(db[:work_cycle_reported_issues].first).to include(
      work_cycle_id: work_cycle_id,
      reported_issue_id: reported_issue.fetch(:id)
    )
  end

  it 'moves a passing Reviewer to Worker review before Worker runs' do
    review_id = insert_review(state: 'reviewer_review')
    reviewer_work_cycle_id = insert_work_cycle(review_id: review_id, role: 'reviewer')

    described_class.call(
      work_cycle_id: reviewer_work_cycle_id,
      work_cycle_result: review_result(reviewer_work_cycle_id, role: 'reviewer', reported_issues: [])
    )

    expect(db[:reviews].where(id: review_id).get(:state)).to eq('worker_review')
    expect(db[:reported_issues].count).to eq(0)
  end

  it 'moves a passing Reviewer directly to Manager review after Worker ran' do
    review_id = insert_review(state: 'reviewer_review')
    worker_work_cycle_id = insert_work_cycle(review_id: review_id, role: 'worker')
    db[:work_cycles].where(id: worker_work_cycle_id).update(completed_at: Time.now)
    reviewer_work_cycle_id = insert_work_cycle(review_id: review_id, role: 'reviewer')

    described_class.call(
      work_cycle_id: reviewer_work_cycle_id,
      work_cycle_result: review_result(reviewer_work_cycle_id, role: 'reviewer', reported_issues: [])
    )

    expect(db[:reviews].where(id: review_id).get(:state)).to eq('manager_review')
    expect(db[:reported_issues].count).to eq(0)
  end

  it 'moves a passing Worker review to Manager review' do
    review_id = insert_review(state: 'worker_review')
    worker_work_cycle_id = insert_work_cycle(review_id: review_id, role: 'worker')

    described_class.call(
      work_cycle_id: worker_work_cycle_id,
      work_cycle_result: review_result(worker_work_cycle_id, role: 'worker', reported_issues: [])
    )

    expect(db[:reviews].where(id: review_id).get(:state)).to eq('manager_review')
    expect(db[:reported_issues].count).to eq(0)
  end

  it 'atomically stores Manager-reported issues and their relationships' do
    review_id = insert_review(state: 'manager_review')
    work_cycle_id = insert_work_cycle(review_id: review_id, role: 'manager')

    described_class.call(
      work_cycle_id: work_cycle_id,
      work_cycle_result: review_result(
        work_cycle_id,
        role: 'manager',
        reported_issues: ['First Manager issue.', 'Second Manager issue.']
      )
    )

    issues = db[:reported_issues].order(:id).all
    expect(issues).to match(
      [
        include(source: 'manager', body: 'First Manager issue.', decision: nil),
        include(source: 'manager', body: 'Second Manager issue.', decision: nil),
      ]
    )
    expect(db[:review_issues].order(:id).select_map(%i[review_id reported_issue_id])).to eq(
      issues.map { |issue| [review_id, issue.fetch(:id)] }
    )
    expect(db[:work_cycle_reported_issues].order(:id).select_map(%i[work_cycle_id reported_issue_id])).
      to eq(issues.map { |issue| [work_cycle_id, issue.fetch(:id)] })
    expect(db[:reviews].where(id: review_id).get(:state)).to eq('manager_issues_assessment')
  end

  it 'stores a passing Manager review and enters finalization' do
    review_id = insert_review(state: 'manager_review')
    work_cycle_id = insert_work_cycle(review_id: review_id, role: 'manager')

    described_class.call(
      work_cycle_id: work_cycle_id,
      work_cycle_result: review_result(work_cycle_id, role: 'manager', reported_issues: [])
    )

    expect(db[:work_cycles].where(id: work_cycle_id).first).to include(
      completed_at: be_a(Time),
      provider: 'openai-codex',
      model: 'gpt-5.6-sol',
      reasoning_level: 'high'
    )
    expect(db[:reviews].where(id: review_id).get(:state)).to eq('manager_finalizing')
  end

  it 'rolls back completion, reported issues, relationships, and state when persistence fails' do
    review_id = insert_review(state: 'reviewer_review')
    work_cycle_id = insert_work_cycle(review_id: review_id, role: 'reviewer')
    result = review_result(
      work_cycle_id,
      role: 'reviewer',
      reported_issues: ['Rolled back issue.', nil]
    )

    expect do
      described_class.call(work_cycle_id: work_cycle_id, work_cycle_result: result)
    end.to raise_error(Sequel::NotNullConstraintViolation)

    expect(db[:work_cycles].where(id: work_cycle_id).first).to include(
      completed_at: nil,
      provider: nil,
      model: nil,
      reasoning_level: nil
    )
    expect(db[:reviews].where(id: review_id).get(:state)).to eq('reviewer_review')
    expect(db[:reported_issues].count).to eq(0)
    expect(db[:review_issues].count).to eq(0)
    expect(db[:work_cycle_reported_issues].count).to eq(0)
  end

  def insert_review(state:, number: 1)
    db[:reviews].insert(
      created_at: Time.now,
      completed_at: nil,
      project_path: '/project',
      number: number,
      source: 'local',
      branch_name: 'feature',
      starting_commit_sha: 'starting-sha',
      original_base_ref: 'origin/main',
      original_base_commit_sha: 'base-sha',
      active_base_ref: 'origin/main',
      active_base_commit_sha: 'base-sha',
      state: state
    )
  end

  def insert_work_cycle(review_id:, role:)
    db[:work_cycles].insert(
      created_at: Time.now,
      completed_at: nil,
      review_id: review_id,
      role: role,
      action: 'review',
      provider: nil,
      model: nil,
      reasoning_level: nil
    )
  end

  def review_result(work_cycle_id, role:, reported_issues:)
    {
      'work_cycle_id' => work_cycle_id,
      'role' => role,
      'action' => 'review',
      'status' => 'completed',
      'provider' => 'openai-codex',
      'model' => 'gpt-5.6-sol',
      'reasoning_level' => 'high',
      'reported_issues' => reported_issues
    }
  end
end
