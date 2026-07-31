# frozen_string_literal: true

require 'json'
require_relative 'spec_helper'

RSpec.describe StoreWorkCycleCompletion do
  let(:db) { Database.connection }

  it 'atomically stores Reviewer findings and their relationships in result order' do
    review_id = insert_review(state: 'reviewer_review')
    work_cycle_id = insert_work_cycle(review_id: review_id, role: 'reviewer')
    result = review_result(work_cycle_id, role: 'reviewer', findings: ["First finding.\n", 'Second finding.'])

    described_class.call(work_cycle_id: work_cycle_id, work_cycle_result: result)

    expect(db[:work_cycles].where(id: work_cycle_id).first).to include(
      completed_at: be_a(Time),
      result: JSON.generate(result),
      provider: 'openai-codex',
      model: 'gpt-5.6-sol',
      reasoning_level: 'high',
      commit_sha: nil
    )
    expect(db[:reviews].where(id: review_id).get(:state)).to eq('manager_finding_selection')
    findings = db[:reported_issues].order(:id).all
    expect(findings).to match(
      [
        include(source: 'reviewer', source_id: nil, body: "First finding.\n", decision: nil),
        include(source: 'reviewer', source_id: nil, body: 'Second finding.', decision: nil),
      ]
    )
    expect(db[:review_issues].order(:id).select_map(%i[review_id reported_issue_id])).to eq(
      findings.map { |finding| [review_id, finding.fetch(:id)] }
    )
    expect(db[:work_cycle_findings].order(:id).select_map(%i[work_cycle_id reported_issue_id])).to eq(
      findings.map { |finding| [work_cycle_id, finding.fetch(:id)] }
    )
  end

  it 'stores final Worker review findings with the Worker source' do
    review_id = insert_review(state: 'worker_review')
    work_cycle_id = insert_work_cycle(review_id: review_id, role: 'worker')
    result = review_result(work_cycle_id, role: 'worker', findings: ['Worker finding.'])

    described_class.call(work_cycle_id: work_cycle_id, work_cycle_result: result)

    finding = db[:reported_issues].first
    expect(finding).to include(source: 'worker', source_id: nil, body: 'Worker finding.', decision: nil)
    expect(db[:reviews].where(id: review_id).get(:state)).to eq('manager_finding_selection')
    expect(db[:review_issues].get(:reported_issue_id)).to eq(finding.fetch(:id))
    expect(db[:work_cycle_findings].first).to include(
      work_cycle_id: work_cycle_id,
      reported_issue_id: finding.fetch(:id)
    )
  end

  it 'keeps passing review transitions unchanged' do
    reviewer_review_id = insert_review(number: 1, state: 'reviewer_review')
    reviewer_work_cycle_id = insert_work_cycle(review_id: reviewer_review_id, role: 'reviewer')
    worker_review_id = insert_review(number: 2, state: 'worker_review')
    worker_work_cycle_id = insert_work_cycle(review_id: worker_review_id, role: 'worker')

    described_class.call(
      work_cycle_id: reviewer_work_cycle_id,
      work_cycle_result: review_result(reviewer_work_cycle_id, role: 'reviewer', findings: [])
    )
    described_class.call(
      work_cycle_id: worker_work_cycle_id,
      work_cycle_result: review_result(worker_work_cycle_id, role: 'worker', findings: [])
    )

    expect(db[:reviews].where(id: reviewer_review_id).get(:state)).to eq('worker_review')
    expect(db[:reviews].where(id: worker_review_id).get(:state)).to eq('manager_review')
    expect(db[:reported_issues].count).to eq(0)
  end

  it 'rolls back completion, findings, relationships, and state when persistence fails' do
    review_id = insert_review(state: 'reviewer_review')
    work_cycle_id = insert_work_cycle(review_id: review_id, role: 'reviewer')
    result = review_result(work_cycle_id, role: 'reviewer', findings: ['Rolled back finding.', nil])

    expect do
      described_class.call(work_cycle_id: work_cycle_id, work_cycle_result: result)
    end.to raise_error(Sequel::NotNullConstraintViolation)

    expect(db[:work_cycles].where(id: work_cycle_id).first).to include(
      completed_at: nil,
      result: nil,
      provider: nil,
      model: nil,
      reasoning_level: nil
    )
    expect(db[:reviews].where(id: review_id).get(:state)).to eq('reviewer_review')
    expect(db[:reported_issues].count).to eq(0)
    expect(db[:review_issues].count).to eq(0)
    expect(db[:work_cycle_findings].count).to eq(0)
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
      state: state,
      final_commit_sha: nil
    )
  end

  def insert_work_cycle(review_id:, role:)
    db[:work_cycles].insert(
      created_at: Time.now,
      completed_at: nil,
      review_id: review_id,
      previous_work_cycle_id: nil,
      role: role,
      action: 'review',
      result: nil,
      provider: nil,
      model: nil,
      reasoning_level: nil,
      commit_sha: nil
    )
  end

  def review_result(work_cycle_id, role:, findings:)
    {
      'work_cycle_id' => work_cycle_id,
      'role' => role,
      'action' => 'review',
      'status' => 'completed',
      'provider' => 'openai-codex',
      'model' => 'gpt-5.6-sol',
      'reasoning_level' => 'high',
      'findings' => findings
    }
  end
end
