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
      starting_commit_sha: 'starting-sha',
      state: 'initialized',
      super_review_agent: 'claude'
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

  it 'commits a whole-task correction and starts its scoped Reviewer review' do
    db[:tasks].where(id: task_id).update(state: 'super_review')
    insert_implementation(step_number: 1, completed_at: Time.now)
    previous_review_id = insert_review(completed_at: Time.now)
    issue_id = insert_produced_issue(previous_review_id, decision: 'approved')
    correction_id = insert_implementation(step_number: nil)
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
      message: 'Final review correction 1'
    )
    expect(output).to eq(
      "Worker implementation completed (Cycle #{correction_id}, Whole Task).\n" \
      "AutoImplementCycle #{reviewer_work_cycle.fetch(:id)}"
    )
    expect(reviewer_work_cycle).to include(role: 'reviewer', action: 'review')
    expect(db[:work_cycle_inputs].where(work_cycle_id: reviewer_work_cycle.fetch(:id)).
      select_map(:reported_issue_id)).to eq([issue_id])
  end

  it 'commits a Manager correction with the whole-task correction subject' do
    db[:tasks].where(id: task_id).update(state: 'manager_review')
    manager_review_id = insert_manager_review(completed_at: Time.now)
    issue_id = insert_produced_issue(manager_review_id, decision: 'approved', source: 'manager')
    correction_id = insert_implementation(step_number: nil)
    db[:work_cycle_inputs].insert(
      created_at: Time.now,
      work_cycle_id: correction_id,
      reported_issue_id: issue_id
    )
    write_result(correction_id, implementation_result(correction_id))

    output = described_class.call(work_cycle_id: correction_id)
    scoped_review = db[:work_cycles].order(:id).last

    expect(CommitWorkCycle).to have_received(:call).with(
      project_path: project_path,
      message: 'Final review correction 1'
    )
    expect(output).to eq(
      "Worker implementation completed (Cycle #{correction_id}, Whole Task).\n" \
      "AutoImplementCycle #{scoped_review.fetch(:id)}"
    )
    expect(scoped_review).to include(role: 'reviewer', action: 'review', completed_at: nil)
  end

  it 'uses the next whole-task correction number after an earlier correction completed' do
    db[:tasks].where(id: task_id).update(state: 'super_review')
    first_review_id = insert_review(completed_at: Time.now)
    first_issue_id = insert_produced_issue(first_review_id, decision: 'approved')
    first_correction_id = insert_implementation(step_number: nil, completed_at: Time.now)
    db[:work_cycle_inputs].insert(
      created_at: Time.now,
      work_cycle_id: first_correction_id,
      reported_issue_id: first_issue_id
    )
    second_review_id = insert_review(completed_at: Time.now)
    second_issue_id = insert_produced_issue(second_review_id, decision: 'approved')
    second_correction_id = insert_implementation(step_number: nil)
    db[:work_cycle_inputs].insert(
      created_at: Time.now,
      work_cycle_id: second_correction_id,
      reported_issue_id: second_issue_id
    )
    write_result(second_correction_id, implementation_result(second_correction_id))

    described_class.call(work_cycle_id: second_correction_id)

    expect(CommitWorkCycle).to have_received(:call).with(
      project_path: project_path,
      message: 'Final review correction 2'
    )
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

  it 'stores final Worker findings and displays the first issue without committing' do
    db[:tasks].where(id: task_id).update(state: 'worker_final_review')
    insert_implementation(step_number: 1, completed_at: Time.now)
    insert_review(completed_at: Time.now)
    worker_review_id = insert_worker_review
    write_result(worker_review_id, worker_review_result(worker_review_id, ['Final Worker issue.']))

    output = described_class.call(work_cycle_id: worker_review_id)
    issue = db[:reported_issues].first

    expect(output).to eq(
      "Worker review completed (Cycle #{worker_review_id}). Reported issues:\n" \
      "- Final Worker issue.\n\nIssue: #{issue.fetch(:id)}\n\n> Final Worker issue."
    )
    expect(issue).to include(source: 'worker', decision: nil)
    expect(CommitWorkCycle).not_to have_received(:call)
    expect(db[:tasks].where(id: task_id).get(:state)).to eq('worker_final_review')
  end

  it 'starts Manager review after a clean final Worker result' do
    db[:tasks].where(id: task_id).update(state: 'worker_final_review')
    insert_implementation(step_number: 1, completed_at: Time.now)
    insert_review(completed_at: Time.now)
    worker_review_id = insert_worker_review
    write_result(worker_review_id, worker_review_result(worker_review_id, []))

    output = described_class.call(work_cycle_id: worker_review_id)
    manager_review = db[:work_cycles].order(:id).last

    expect(output).to eq(
      "Worker review completed (Cycle #{worker_review_id}). Reported issues:\n" \
      "- None\nAutoImplementCycle #{manager_review.fetch(:id)}"
    )
    expect(manager_review).to include(role: 'manager', action: 'review', completed_at: nil)
    expect(db[:tasks].where(id: task_id).get(:state)).to eq('manager_review')
    expect(CommitWorkCycle).not_to have_received(:call)
  end

  it 'stores Manager findings with Manager provenance and displays the first issue' do
    db[:tasks].where(id: task_id).update(state: 'manager_review')
    manager_review_id = insert_manager_review
    write_result(manager_review_id, manager_review_result(manager_review_id, ['Manager issue.']))

    output = described_class.call(work_cycle_id: manager_review_id)
    issue = db[:reported_issues].first

    expect(output).to eq(
      "Manager review completed (Cycle #{manager_review_id}). Reported issues:\n" \
      "- Manager issue.\n\nIssue: #{issue.fetch(:id)}\n\n> Manager issue."
    )
    expect(issue).to include(source: 'manager', decision: nil)
    expect(CommitWorkCycle).not_to have_received(:call)
    expect(File.exist?(result_path(manager_review_id))).to be(false)
  end

  it 'runs final checks after storing a clean Manager review' do
    db[:tasks].where(id: task_id).update(state: 'manager_review')
    manager_review_id = insert_manager_review
    write_result(manager_review_id, manager_review_result(manager_review_id, []))
    allow(RunTaskFinalChecks).to receive(:call).and_return('Task completed output.')

    output = described_class.call(work_cycle_id: manager_review_id)

    expect(output).to eq(
      "Manager review completed (Cycle #{manager_review_id}). Reported issues:\n" \
      "- None\nTask completed output."
    )
    expect(RunTaskFinalChecks).to have_received(:call).with(task_id: task_id)
    expect(File.exist?(result_path(manager_review_id))).to be(false)
  end

  it 'reports a Reviewer result missing its required issue list as a participant-result failure' do
    insert_implementation(step_number: 1, completed_at: Time.now)
    reviewer_work_cycle_id = insert_review
    write_result(
      reviewer_work_cycle_id,
      completed_result(reviewer_work_cycle_id).merge('role' => 'reviewer', 'action' => 'review')
    )

    expect { described_class.call(work_cycle_id: reviewer_work_cycle_id) }.
      to raise_error(
        RuntimeError,
        /Task #{task_id} Work Cycle #{reviewer_work_cycle_id} participant result failed at .*--retry/
      )

    expect(db[:work_cycles].where(id: reviewer_work_cycle_id).get(:completed_at)).to be_nil
    expect(File.exist?(result_path(reviewer_work_cycle_id))).to be(true)
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

  it 'accepts a clean Reviewer pass and starts the next authored step' do
    insert_implementation(step_number: 1, completed_at: Time.now)
    reviewer_work_cycle_id = insert_review
    write_result(reviewer_work_cycle_id, review_result(reviewer_work_cycle_id, []))

    output = described_class.call(work_cycle_id: reviewer_work_cycle_id)
    next_implementation = db[:work_cycles].order(:id).last

    expect(output).to eq(
      "Reviewer review completed (Cycle #{reviewer_work_cycle_id}). Reported issues:\n" \
      "- None\nStep 1 accepted.\nAutoImplementCycle #{next_implementation.fetch(:id)}"
    )
    expect(next_implementation).to include(step_number: 2, role: 'worker', action: 'implementation')
    expect(db[:tasks].where(id: task_id).get(:state)).to eq('initialized')
    expect(db[:work_cycles].count).to eq(3)
    expect(File.exist?(result_path(reviewer_work_cycle_id))).to be(false)
  end

  it 'continues to the next step after a correction receives a clean Reviewer pass' do
    insert_implementation(step_number: 1, completed_at: Time.now)
    first_review_id = insert_review(completed_at: Time.now)
    issue_id = insert_produced_issue(first_review_id, decision: 'approved')
    correction_id = insert_implementation(step_number: 1, completed_at: Time.now)
    db[:work_cycle_inputs].insert(
      created_at: Time.now,
      work_cycle_id: correction_id,
      reported_issue_id: issue_id
    )
    final_review_id = insert_review
    write_result(final_review_id, review_result(final_review_id, []))

    output = described_class.call(work_cycle_id: final_review_id)
    next_implementation = db[:work_cycles].order(:id).last

    expect(output).to end_with(
      "Step 1 accepted.\nAutoImplementCycle #{next_implementation.fetch(:id)}"
    )
    expect(next_implementation.fetch(:step_number)).to eq(2)
  end

  it 'starts super-review after the last step is accepted' do
    File.write(File.join(task_path, 'steps.md'), "# Steps\n\n## Step 1: Build it\n")
    insert_implementation(step_number: 1, completed_at: Time.now)
    reviewer_work_cycle_id = insert_review
    write_result(reviewer_work_cycle_id, review_result(reviewer_work_cycle_id, []))

    output = described_class.call(work_cycle_id: reviewer_work_cycle_id)
    super_review_work_cycle = db[:work_cycles].order(:id).last

    expect(output).to eq(
      "Reviewer review completed (Cycle #{reviewer_work_cycle_id}). Reported issues:\n" \
      "- None\nStep 1 accepted.\nAutoImplementCycle #{super_review_work_cycle.fetch(:id)}"
    )
    expect(db[:tasks].where(id: task_id).get(:state)).to eq('super_review')
    expect(super_review_work_cycle).to include(role: 'reviewer', action: 'review')
    expect(db[:work_cycles].count).to eq(3)
  end

  it 'retains a failed result without committing or completing' do
    work_cycle_id = insert_implementation(step_number: 1)
    write_result(
      work_cycle_id,
      implementation_result(work_cycle_id).merge('status' => 'failed', 'error' => 'Could not implement.')
    )

    expect { described_class.call(work_cycle_id: work_cycle_id) }.
      to raise_error(
        RuntimeError,
        /Task #{task_id} Work Cycle #{work_cycle_id} participant result failed at .*#{work_cycle_id}\.json.*--retry/
      )

    expect(CommitWorkCycle).not_to have_received(:call)
    expect(db[:work_cycles].where(id: work_cycle_id).get(:completed_at)).to be_nil
    expect(File.exist?(result_path(work_cycle_id))).to be(true)
  end

  it 'retains malformed or mismatched result transport' do
    work_cycle_id = insert_implementation(step_number: 1)
    path = result_path(work_cycle_id)
    created_result_paths << path
    File.write(path, '{')

    expect { described_class.call(work_cycle_id: work_cycle_id) }.
      to raise_error(
        RuntimeError,
        /Task #{task_id} Work Cycle #{work_cycle_id} participant result failed at .*#{work_cycle_id}\.json.*--retry/
      )
    expect(File.exist?(result_path(work_cycle_id))).to be(true)

    write_result(
      work_cycle_id,
      implementation_result(work_cycle_id).merge('work_cycle_id' => work_cycle_id + 1)
    )
    expect { described_class.call(work_cycle_id: work_cycle_id) }.
      to raise_error(
        RuntimeError,
        /Task #{task_id} Work Cycle #{work_cycle_id} participant result failed at .*#{work_cycle_id}\.json.*--retry/
      )
    expect(db[:work_cycles].where(id: work_cycle_id).get(:completed_at)).to be_nil
    expect(File.exist?(result_path(work_cycle_id))).to be(true)
  end

  it 'retains an implementation result when no managed commit can be created' do
    work_cycle_id = insert_implementation(step_number: 1)
    write_result(work_cycle_id, implementation_result(work_cycle_id))
    allow(CommitWorkCycle).to receive(:call).and_raise('git commit failed')

    expect { described_class.call(work_cycle_id: work_cycle_id) }.
      to raise_error(
        RuntimeError,
        /Task #{task_id} Work Cycle #{work_cycle_id} Git commit failed.*normal resume.*ad-hoc Manager handling/
      )

    expect(db[:work_cycles].where(id: work_cycle_id).get(:completed_at)).to be_nil
    expect(File.exist?(result_path(work_cycle_id))).to be(true)
  end

  it 'retains a committed implementation result when database persistence fails' do
    work_cycle_id = insert_implementation(step_number: 1)
    write_result(work_cycle_id, implementation_result(work_cycle_id))
    allow(StoreTaskWorkCycleCompletion).to receive(:call).and_raise('database failed')

    expect { described_class.call(work_cycle_id: work_cycle_id) }.
      to raise_error(
        RuntimeError,
        /Task #{task_id} Work Cycle #{work_cycle_id} database completion failed.*ad-hoc Manager handling.*not retry/
      )

    expect(CommitWorkCycle).to have_received(:call)
    expect(db[:work_cycles].where(id: work_cycle_id).get(:completed_at)).to be_nil
    expect(File.exist?(result_path(work_cycle_id))).to be(true)
  end

  it 'reports transport cleanup failure after durable completion without retrying' do
    work_cycle_id = insert_implementation(step_number: 1)
    write_result(work_cycle_id, implementation_result(work_cycle_id))
    allow(File).to receive(:delete).with(result_path(work_cycle_id)).and_raise(Errno::EACCES)

    error_pattern = Regexp.new(
      "Task #{task_id} Work Cycle #{work_cycle_id} transport cleanup failed at .*" \
      "#{work_cycle_id}\\.json.*ad-hoc Manager handling.*not retry"
    )
    expect { described_class.call(work_cycle_id: work_cycle_id) }.
      to raise_error(RuntimeError, error_pattern)

    expect(db[:work_cycles].where(id: work_cycle_id).get(:completed_at)).to be_a(Time)
    expect(File.exist?(result_path(work_cycle_id))).to be(true)
  end

  it 'rejects Reviewer mutations and retains the result' do
    insert_implementation(step_number: 1, completed_at: Time.now)
    reviewer_work_cycle_id = insert_review
    write_result(reviewer_work_cycle_id, review_result(reviewer_work_cycle_id, []))
    allow(ValidateCleanGitState).to receive(:call).and_raise('Working tree is not clean')

    expect { described_class.call(work_cycle_id: reviewer_work_cycle_id) }.
      to raise_error(
        RuntimeError,
        /Task #{task_id} Work Cycle #{reviewer_work_cycle_id} Git review validation failed.*normal resume/
      )

    expect(CommitWorkCycle).not_to have_received(:call)
    expect(db[:work_cycles].where(id: reviewer_work_cycle_id).get(:completed_at)).to be_nil
    expect(File.exist?(result_path(reviewer_work_cycle_id))).to be(true)
  end

  it 'retains a review result when Reported Issue persistence rolls back' do
    insert_implementation(step_number: 1, completed_at: Time.now)
    reviewer_work_cycle_id = insert_review
    write_result(reviewer_work_cycle_id, review_result(reviewer_work_cycle_id, ['Stored issue.', nil]))

    expect { described_class.call(work_cycle_id: reviewer_work_cycle_id) }.
      to raise_error(
        RuntimeError,
        /Task #{task_id} Work Cycle #{reviewer_work_cycle_id} database completion failed.*ad-hoc Manager handling/
      )

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

  def insert_worker_review(completed_at: nil)
    db[:work_cycles].insert(
      created_at: Time.now,
      completed_at: completed_at,
      task_id: task_id,
      role: 'worker',
      action: 'review'
    )
  end

  def insert_manager_review(completed_at: nil)
    db[:work_cycles].insert(
      created_at: Time.now,
      completed_at: completed_at,
      task_id: task_id,
      role: 'manager',
      action: 'review'
    )
  end

  def insert_produced_issue(work_cycle_id, decision:, source: 'reviewer')
    issue_id = StoreIssue.call(project_path: project_path, source: source, body: 'Approved correction.')
    db[:reported_issues].where(id: issue_id).update(
      decision: decision,
      decision_reason: "#{decision.capitalize} in spec."
    )
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

  def worker_review_result(work_cycle_id, reported_issues)
    completed_result(work_cycle_id).merge(
      'role' => 'worker',
      'action' => 'review',
      'reported_issues' => reported_issues
    )
  end

  def manager_review_result(work_cycle_id, reported_issues)
    completed_result(work_cycle_id).merge(
      'role' => 'manager',
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
