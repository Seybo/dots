# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe 'AcceptedTaskStepNumbers' do
  let(:service_class) { Object.const_get(:AcceptedTaskStepNumbers) }
  let(:db) { Database.connection }
  let(:task_id) do
    db[:tasks].insert(
      created_at: Time.now,
      task_path: '/tasks/1',
      project_path: '/project',
      starting_commit_sha: 'starting-sha',
      state: 'initialized'
    )
  end

  it 'accepts a clean Reviewer pass' do
    insert_implementation(step_number: 8)
    insert_review

    expect(accepted_step_numbers).to eq([8])
  end

  it 'accepts a skipped-only Reviewer pass' do
    insert_implementation(step_number: 8)
    insert_review(issue_decisions: ['skipped'])

    expect(accepted_step_numbers).to eq([8])
  end

  it 'does not accept approved or undecided Reviewer findings' do
    insert_implementation(step_number: 8)
    insert_review(issue_decisions: ['approved'])
    insert_implementation(step_number: 2)
    insert_review(issue_decisions: [nil])

    expect(accepted_step_numbers).to be_empty
  end

  it 'accepts a correction only after its clean Reviewer pass' do
    insert_implementation(step_number: 8)
    insert_review
    insert_implementation(step_number: 8)

    expect(accepted_step_numbers).to be_empty

    insert_review

    expect(accepted_step_numbers).to eq([8])
  end

  def accepted_step_numbers
    service_class.call(connection: db, task_id: task_id)
  end

  def insert_implementation(step_number:)
    db[:work_cycles].insert(
      created_at: Time.now,
      completed_at: Time.now,
      task_id: task_id,
      step_number: step_number,
      role: 'worker',
      action: 'implementation'
    )
  end

  def insert_review(issue_decisions: [])
    work_cycle_id = db[:work_cycles].insert(
      created_at: Time.now,
      completed_at: Time.now,
      task_id: task_id,
      role: 'reviewer',
      action: 'review'
    )
    issue_decisions.each do |decision|
      issue_id = StoreIssue.call(project_path: '/project', source: 'reviewer', body: 'Review issue.')
      unless decision.nil?
        db[:reported_issues].where(id: issue_id).update(
          decision: decision,
          decision_reason: "#{decision.capitalize} in spec."
        )
      end
      db[:work_cycle_reported_issues].insert(
        created_at: Time.now,
        work_cycle_id: work_cycle_id,
        reported_issue_id: issue_id
      )
    end
  end
end
