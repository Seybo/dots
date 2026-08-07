# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'tmpdir'
require_relative '../../spec/spec_helper'

RSpec.describe WaitTaskWorkCycle do
  let(:db) { Database.connection }
  let(:task_path) { Dir.mktmpdir('wait-task-work-cycle-spec') }
  let(:created_result_paths) { [] }
  let(:task_id) do
    db[:tasks].insert(
      created_at: Time.now,
      task_path: task_path,
      project_path: project_path,
      branch_name: 'feature',
      starting_commit_sha: 'starting-sha',
      state: 'initialized'
    )
  end

  before do
    File.write(
      File.join(task_path, 'steps.md'),
      "# Steps\n\n## Step 1: Build it\n\n## Step 2\n"
    )
    allow(CommitWorkCycle).to receive(:call)
    allow(ValidateCleanGitState).to receive(:call).and_return('head-sha')
  end

  after do
    created_result_paths.each { |path| FileUtils.rm_f(path) }
    FileUtils.remove_entry(task_path)
  end

  it 'commits an initial implementation, stores provenance, and starts Reviewer review' do
    work_cycle_id = insert_implementation(step_number: 1)
    write_result(work_cycle_id, implementation_result(work_cycle_id))

    output = described_class.call(work_cycle_id: work_cycle_id)
    reviewer_work_cycle = db[:work_cycles].order(:id).last

    expect(output).to eq(
      "Worker implementation completed (Cycle #{work_cycle_id}, Step 1).\n" \
      "AutoImplementCycle #{reviewer_work_cycle.fetch(:id)}"
    )
    expect(CommitWorkCycle).to have_received(:call).with(
      project_path: project_path,
      message: 'Step 1: Build it'
    )
    expect(db[:work_cycles].where(id: work_cycle_id).first).to include(
      completed_at: be_a(Time),
      provider: 'openai-codex',
      model: 'gpt-5.6-sol',
      reasoning_level: 'high'
    )
    expect(reviewer_work_cycle).to include(role: 'reviewer', action: 'review', completed_at: nil)
    expect(db[:tasks].where(id: task_id).get(:state)).to eq('initialized')
    expect(File.exist?(result_path(work_cycle_id))).to be(false)
  end

  it 'uses the step number when the initial authored heading has no title' do
    work_cycle_id = insert_implementation(step_number: 2)
    write_result(work_cycle_id, implementation_result(work_cycle_id))

    described_class.call(work_cycle_id: work_cycle_id)

    expect(CommitWorkCycle).to have_received(:call).with(
      project_path: project_path,
      message: 'Step 2'
    )
  end

  it 'commits a correction with its exact number and starts fresh Reviewer review' do
    insert_implementation(step_number: 1, completed_at: Time.now)
    previous_review_id = insert_review(completed_at: Time.now)
    issue_id = insert_produced_issue(previous_review_id, decision: 'approved')
    correction_id = insert_implementation(step_number: 1)
    db[:work_cycle_inputs].insert(
      created_at: Time.now,
      work_cycle_id: correction_id,
      reported_issue_id: issue_id
    )
    write_result(correction_id, implementation_result(correction_id))

    output = described_class.call(work_cycle_id: correction_id)
    reviewer_work_cycle = db[:work_cycles].order(:id).last

    expect(CommitWorkCycle).to have_received(:call).with(
      project_path: project_path,
      message: 'Step 1 correction 1'
    )
    expect(output).to eq(
      "Worker implementation completed (Cycle #{correction_id}, Step 1).\n" \
      "AutoImplementCycle #{reviewer_work_cycle.fetch(:id)}"
    )
    expect(db[:work_cycle_inputs].where(work_cycle_id: reviewer_work_cycle.fetch(:id)).
      select_map(:reported_issue_id)).to eq([issue_id])
  end

  it 'uses the next correction number after an earlier correction completed' do
    insert_implementation(step_number: 1, completed_at: Time.now)
    first_review_id = insert_review(completed_at: Time.now)
    first_issue_id = insert_produced_issue(first_review_id, decision: 'approved')
    first_correction_id = insert_implementation(step_number: 1, completed_at: Time.now)
    db[:work_cycle_inputs].insert(
      created_at: Time.now,
      work_cycle_id: first_correction_id,
      reported_issue_id: first_issue_id
    )
    second_review_id = insert_review(completed_at: Time.now)
    second_issue_id = insert_produced_issue(second_review_id, decision: 'approved')
    second_correction_id = insert_implementation(step_number: 1)
    db[:work_cycle_inputs].insert(
      created_at: Time.now,
      work_cycle_id: second_correction_id,
      reported_issue_id: second_issue_id
    )
    write_result(second_correction_id, implementation_result(second_correction_id))

    described_class.call(work_cycle_id: second_correction_id)

    expect(CommitWorkCycle).to have_received(:call).with(
      project_path: project_path,
      message: 'Step 1 correction 2'
    )
  end

  it 'stores Reviewer issues without committing and displays the first issue' do
    insert_implementation(step_number: 1, completed_at: Time.now)
    reviewer_work_cycle_id = insert_review
    write_result(
      reviewer_work_cycle_id,
      review_result(reviewer_work_cycle_id, ['First review issue.', 'Second review issue.'])
    )

    output = described_class.call(work_cycle_id: reviewer_work_cycle_id)
    issues = db[:reported_issues].order(:id).all

    expect(output).to eq(
      "Reviewer review completed (Cycle #{reviewer_work_cycle_id}). Reported issues:\n" \
      "- First review issue.\n- Second review issue.\n\n" \
      "Issue: #{issues.first.fetch(:id)}\n\n> First review issue."
    )
    expect(CommitWorkCycle).not_to have_received(:call)
    expect(ValidateCleanGitState).to have_received(:call).with(project_path: project_path)
    expect(db[:work_cycles].where(id: reviewer_work_cycle_id).get(:completed_at)).to be_a(Time)
    expect(db[:work_cycle_reported_issues].where(work_cycle_id: reviewer_work_cycle_id).
      select_map(:reported_issue_id)).to eq(issues.map { |issue| issue.fetch(:id) })
    expect(File.exist?(result_path(reviewer_work_cycle_id))).to be(false)
  end

  it 'accepts a clean Reviewer pass and leaves the Task initialized' do
    insert_implementation(step_number: 1, completed_at: Time.now)
    reviewer_work_cycle_id = insert_review
    write_result(reviewer_work_cycle_id, review_result(reviewer_work_cycle_id, []))

    output = described_class.call(work_cycle_id: reviewer_work_cycle_id)

    expect(output).to eq(
      "Reviewer review completed (Cycle #{reviewer_work_cycle_id}). Reported issues:\n" \
      "- None\nStep 1 accepted."
    )
    expect(db[:tasks].where(id: task_id).get(:state)).to eq('initialized')
    expect(db[:work_cycles].count).to eq(2)
    expect(File.exist?(result_path(reviewer_work_cycle_id))).to be(false)
  end

  it 'retains a failed result without committing or completing' do
    work_cycle_id = insert_implementation(step_number: 1)
    write_result(
      work_cycle_id,
      implementation_result(work_cycle_id).merge('status' => 'failed', 'error' => 'Could not implement.')
    )

    expect { described_class.call(work_cycle_id: work_cycle_id) }.
      to raise_error(RuntimeError, "Work Cycle #{work_cycle_id} failed: Could not implement.")

    expect(CommitWorkCycle).not_to have_received(:call)
    expect(db[:work_cycles].where(id: work_cycle_id).get(:completed_at)).to be_nil
    expect(File.exist?(result_path(work_cycle_id))).to be(true)
  end

  it 'retains malformed or mismatched result transport' do
    work_cycle_id = insert_implementation(step_number: 1)
    path = result_path(work_cycle_id)
    created_result_paths << path
    File.write(path, '{')

    expect { described_class.call(work_cycle_id: work_cycle_id) }.to raise_error(JSON::ParserError)
    expect(File.exist?(result_path(work_cycle_id))).to be(true)

    write_result(
      work_cycle_id,
      implementation_result(work_cycle_id).merge('work_cycle_id' => work_cycle_id + 1)
    )
    expect { described_class.call(work_cycle_id: work_cycle_id) }.
      to raise_error(RuntimeError, /does not match Work Cycle #{work_cycle_id}/)
    expect(db[:work_cycles].where(id: work_cycle_id).get(:completed_at)).to be_nil
    expect(File.exist?(result_path(work_cycle_id))).to be(true)
  end

  it 'retains an implementation result when no managed commit can be created' do
    work_cycle_id = insert_implementation(step_number: 1)
    write_result(work_cycle_id, implementation_result(work_cycle_id))
    allow(CommitWorkCycle).to receive(:call).and_raise('git commit failed')

    expect { described_class.call(work_cycle_id: work_cycle_id) }.
      to raise_error(RuntimeError, 'git commit failed')

    expect(db[:work_cycles].where(id: work_cycle_id).get(:completed_at)).to be_nil
    expect(File.exist?(result_path(work_cycle_id))).to be(true)
  end

  it 'retains a committed implementation result when database persistence fails' do
    work_cycle_id = insert_implementation(step_number: 1)
    write_result(work_cycle_id, implementation_result(work_cycle_id))
    allow(StoreTaskWorkCycleCompletion).to receive(:call).and_raise('database failed')

    expect { described_class.call(work_cycle_id: work_cycle_id) }.
      to raise_error(RuntimeError, 'database failed')

    expect(CommitWorkCycle).to have_received(:call)
    expect(db[:work_cycles].where(id: work_cycle_id).get(:completed_at)).to be_nil
    expect(File.exist?(result_path(work_cycle_id))).to be(true)
  end

  it 'rejects Reviewer mutations and retains the result' do
    insert_implementation(step_number: 1, completed_at: Time.now)
    reviewer_work_cycle_id = insert_review
    write_result(reviewer_work_cycle_id, review_result(reviewer_work_cycle_id, []))
    allow(ValidateCleanGitState).to receive(:call).and_raise('Working tree is not clean')

    expect { described_class.call(work_cycle_id: reviewer_work_cycle_id) }.
      to raise_error(RuntimeError, 'Working tree is not clean')

    expect(CommitWorkCycle).not_to have_received(:call)
    expect(db[:work_cycles].where(id: reviewer_work_cycle_id).get(:completed_at)).to be_nil
    expect(File.exist?(result_path(reviewer_work_cycle_id))).to be(true)
  end

  it 'retains a review result when Reported Issue persistence rolls back' do
    insert_implementation(step_number: 1, completed_at: Time.now)
    reviewer_work_cycle_id = insert_review
    write_result(reviewer_work_cycle_id, review_result(reviewer_work_cycle_id, ['Stored issue.', nil]))

    expect { described_class.call(work_cycle_id: reviewer_work_cycle_id) }.
      to raise_error(Sequel::NotNullConstraintViolation)

    expect(db[:work_cycles].where(id: reviewer_work_cycle_id).get(:completed_at)).to be_nil
    expect(db[:reported_issues].count).to eq(0)
    expect(File.exist?(result_path(reviewer_work_cycle_id))).to be(true)
  end

  def project_path
    '/project'
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

  def insert_review(completed_at: nil)
    db[:work_cycles].insert(
      created_at: Time.now,
      completed_at: completed_at,
      task_id: task_id,
      role: 'reviewer',
      action: 'review'
    )
  end

  def insert_produced_issue(work_cycle_id, decision:)
    issue_id = StoreIssue.call(project_path: project_path, source: 'reviewer', body: 'Approved correction.')
    db[:reported_issues].where(id: issue_id).update(decision: decision)
    db[:work_cycle_reported_issues].insert(
      created_at: Time.now,
      work_cycle_id: work_cycle_id,
      reported_issue_id: issue_id
    )
    issue_id
  end

  def implementation_result(work_cycle_id)
    completed_result(work_cycle_id).merge('role' => 'worker', 'action' => 'implementation')
  end

  def review_result(work_cycle_id, reported_issues)
    completed_result(work_cycle_id).merge(
      'role' => 'reviewer',
      'action' => 'review',
      'reported_issues' => reported_issues
    )
  end

  def completed_result(work_cycle_id)
    {
      'work_cycle_id' => work_cycle_id,
      'status' => 'completed',
      'provider' => 'openai-codex',
      'model' => 'gpt-5.6-sol',
      'reasoning_level' => 'high'
    }
  end

  def write_result(work_cycle_id, result)
    path = result_path(work_cycle_id)
    created_result_paths << path unless created_result_paths.include?(path)
    File.write(path, JSON.generate(result))
  end

  def result_path(work_cycle_id)
    "/tmp/autoimplement-work-cycle-#{work_cycle_id}.json"
  end
end
