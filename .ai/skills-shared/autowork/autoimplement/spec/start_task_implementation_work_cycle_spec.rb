# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'
require_relative '../../spec/spec_helper'

RSpec.describe 'StartTaskImplementationWorkCycle' do
  let(:service_class) { Object.const_get(:StartTaskImplementationWorkCycle) }
  let(:db) { Database.connection }
  let(:task_path) { Dir.mktmpdir('start-task-work-cycle-spec') }
  let(:project_path) { '/project' }
  let(:task_id) do
    db[:tasks].insert(
      created_at: Time.now,
      task_path: task_path,
      project_path: project_path,
      starting_commit_sha: 'starting-sha',
      state: 'initialized',
      super_review_agent: 'claude'
    )
  end

  before do
    write_steps([8, 2])
    allow(ValidateCleanGitState).to receive(:call).and_return('head-sha')
  end

  after do
    FileUtils.remove_entry(task_path)
  end

  it 'creates one Worker implementation Work Cycle for the first authored step' do
    work_cycle_id = service_class.call(task_id: task_id)

    expect(db[:work_cycles].where(id: work_cycle_id).first).to include(
      task_id: task_id,
      review_id: nil,
      step_number: 8,
      role: 'worker',
      action: 'implementation',
      completed_at: nil
    )
    expect(ValidateCleanGitState).to have_received(:call).with(project_path: project_path)
    expect(db[:tasks].where(id: task_id).get(:state)).to eq('initialized')
  end

  it 'keeps a completed implementation unaccepted until Reviewer passes' do
    insert_implementation(step_number: 8)

    work_cycle_id = service_class.call(task_id: task_id)

    expect(db[:work_cycles].where(id: work_cycle_id).get(:step_number)).to eq(8)
  end

  it 'selects the next authored step after a clean Reviewer pass' do
    insert_implementation(step_number: 8)
    insert_review

    work_cycle_id = service_class.call(task_id: task_id)

    expect(db[:work_cycles].where(id: work_cycle_id).get(:step_number)).to eq(2)
  end

  it 'accepts a skipped-only Reviewer pass' do
    insert_implementation(step_number: 8)
    insert_review(issue_decisions: ['skipped'])

    work_cycle_id = service_class.call(task_id: task_id)

    expect(db[:work_cycles].where(id: work_cycle_id).get(:step_number)).to eq(2)
  end

  it 'keeps approved and undecided Reviewer passes unaccepted' do
    insert_implementation(step_number: 8)
    insert_review(issue_decisions: ['approved'])

    approved_work_cycle_id = service_class.call(task_id: task_id)
    expect(db[:work_cycles].where(id: approved_work_cycle_id).get(:step_number)).to eq(8)

    db[:work_cycles].where(id: approved_work_cycle_id).update(completed_at: Time.now)
    insert_review(issue_decisions: [nil])

    undecided_work_cycle_id = service_class.call(task_id: task_id)
    expect(db[:work_cycles].where(id: undecided_work_cycle_id).get(:step_number)).to eq(8)
  end

  it 'selects the next step after a correction receives a clean Reviewer pass' do
    insert_implementation(step_number: 8)
    insert_review(issue_decisions: ['approved'])
    insert_implementation(step_number: 8)
    insert_review

    work_cycle_id = service_class.call(task_id: task_id)

    expect(db[:work_cycles].where(id: work_cycle_id).get(:step_number)).to eq(2)
  end

  it 'returns nil without checking Git when every authored step was accepted' do
    insert_implementation(step_number: 8)
    insert_review
    insert_implementation(step_number: 2)
    insert_review(issue_decisions: ['skipped'])

    expect(service_class.call(task_id: task_id)).to be_nil

    expect(ValidateCleanGitState).not_to have_received(:call)
    expect(db[:work_cycles].count).to eq(4)
  end

  it 'leaves workflow state unchanged when Git is dirty' do
    allow(ValidateCleanGitState).to receive(:call).and_raise('Working tree is not clean')

    expect { service_class.call(task_id: task_id) }.
      to raise_error(RuntimeError, 'Working tree is not clean')

    expect(db[:work_cycles].count).to eq(0)
    expect(db[:tasks].where(id: task_id).get(:state)).to eq('initialized')
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
      issue_id = StoreIssue.call(project_path: project_path, source: 'reviewer', body: 'Review issue.')
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
    work_cycle_id
  end

  def write_steps(numbers)
    headings = numbers.map { |number| "## Step #{number}: Step #{number}" }.join("\n\n")
    File.write(File.join(task_path, 'steps.md'), "# Steps\n\n#{headings}\n")
  end
end
