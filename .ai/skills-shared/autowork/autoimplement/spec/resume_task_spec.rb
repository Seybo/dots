# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'
require_relative '../../spec/spec_helper'

RSpec.describe 'ResumeTask' do
  let(:service_class) { Object.const_get(:ResumeTask) }
  let(:db) { Database.connection }
  let(:task_path) { Dir.mktmpdir('resume-task-spec') }
  let(:task_id) do
    db[:tasks].insert(
      created_at: Time.now,
      task_path: task_path,
      project_path: '/project',
      starting_commit_sha: 'starting-sha',
      state: 'initialized'
    )
  end

  before do
    File.write(File.join(task_path, 'task.md'), "# Task\n")
    File.write(
      File.join(task_path, 'steps.md'),
      "# Steps\n\n## Step 1: First\n\n## Step 2: Second\n"
    )
    File.write(
      File.join(task_path, 'config.json'),
      JSON.generate(
        'branch' => {
          'name' => 'feature',
          'original_base_ref' => 'origin/main',
          'original_base_commit_sha' => 'base-sha',
          'active_base_ref' => 'origin/main',
          'active_base_commit_sha' => 'base-sha'
        }
      )
    )
    allow(ValidateCleanGitState).to receive(:call).and_return('head-sha')
  end

  after do
    FileUtils.remove_entry(task_path)
  end

  it 'creates and renders one new Worker implementation handoff' do
    output = service_class.call(task_id: task_id)
    work_cycle = db[:work_cycles].first

    expect(output).to eq("AutoImplementCycle #{work_cycle.fetch(:id)}")
    expect(work_cycle).to include(
      task_id: task_id,
      step_number: 1,
      role: 'worker',
      action: 'implementation',
      completed_at: nil
    )
  end

  it 'waits for any incomplete Work Cycle without redispatch or a clean-Git check' do
    implementation_id = insert_implementation
    db[:work_cycles].where(id: implementation_id).update(completed_at: Time.now)
    reviewer_work_cycle_id = insert_review
    allow(ValidateCleanGitState).to receive(:call).and_raise('should not run')

    expect(service_class.call(task_id: task_id)).to eq("WaitWorkCycle #{reviewer_work_cycle_id}")
    expect(db[:work_cycles].count).to eq(2)
  end

  it 'starts Reviewer review after a completed implementation' do
    implementation_id = insert_implementation
    db[:work_cycles].where(id: implementation_id).update(completed_at: Time.now)

    output = service_class.call(task_id: task_id)
    reviewer_work_cycle = db[:work_cycles].order(:id).last

    expect(output).to eq("AutoImplementCycle #{reviewer_work_cycle.fetch(:id)}")
    expect(reviewer_work_cycle).to include(
      task_id: task_id,
      step_number: nil,
      role: 'reviewer',
      action: 'review',
      completed_at: nil
    )
  end

  it 'starts a fresh Reviewer review after a completed correction' do
    insert_implementation(completed_at: Time.now)
    review_work_cycle_id = insert_review(completed_at: Time.now)
    issue_id = insert_produced_issue(review_work_cycle_id, decision: 'approved')
    correction_id = insert_implementation(completed_at: Time.now)
    db[:work_cycle_inputs].insert(
      created_at: Time.now,
      work_cycle_id: correction_id,
      reported_issue_id: issue_id
    )

    output = service_class.call(task_id: task_id)
    reviewer_work_cycle = db[:work_cycles].order(:id).last

    expect(output).to eq("AutoImplementCycle #{reviewer_work_cycle.fetch(:id)}")
    expect(reviewer_work_cycle).to include(role: 'reviewer', action: 'review')
    expect(db[:work_cycle_inputs].where(work_cycle_id: reviewer_work_cycle.fetch(:id)).
      select_map(:reported_issue_id)).to eq([issue_id])
  end

  it 'renders the oldest undecided issue from the latest Reviewer pass' do
    insert_implementation(completed_at: Time.now)
    review_work_cycle_id = insert_review(completed_at: Time.now)
    first_issue_id = insert_produced_issue(review_work_cycle_id)
    insert_produced_issue(review_work_cycle_id, body: 'Second issue.')

    output = service_class.call(task_id: task_id)

    expect(output).to eq("Issue: #{first_issue_id}\n\n> Review issue.")
    expect(db[:work_cycles].count).to eq(2)
  end

  it 'runs every authored-step Reviewer loop before the final gates in order' do
    allow(Database).to receive(:readonly_connection).and_return(db)
    File.write(
      File.join(task_path, 'steps.md'),
      "# Steps\n\n## Step 1: First\n\n## Step 2: Second\n"
    )

    first_implementation_output = service_class.call(task_id: task_id)
    first_implementation = db[:work_cycles].order(:id).last
    db[:work_cycles].where(id: first_implementation.fetch(:id)).update(completed_at: Time.now)

    first_review_output = service_class.call(task_id: task_id)
    first_review = db[:work_cycles].order(:id).last
    first_review_context = JSON.parse(ShowTaskWorkCycle.call(work_cycle_id: first_review.fetch(:id)))
    db[:work_cycles].where(id: first_review.fetch(:id)).update(completed_at: Time.now)

    second_implementation_output = service_class.call(task_id: task_id)
    second_implementation = db[:work_cycles].order(:id).last
    db[:work_cycles].where(id: second_implementation.fetch(:id)).update(completed_at: Time.now)

    second_review_output = service_class.call(task_id: task_id)
    second_review = db[:work_cycles].order(:id).last
    second_review_context = JSON.parse(ShowTaskWorkCycle.call(work_cycle_id: second_review.fetch(:id)))
    db[:work_cycles].where(id: second_review.fetch(:id)).update(completed_at: Time.now)

    super_review_output = service_class.call(task_id: task_id)
    super_review = db[:work_cycles].order(:id).last
    db[:work_cycles].where(id: super_review.fetch(:id)).update(completed_at: Time.now)

    worker_review_output = service_class.call(task_id: task_id)
    worker_review = db[:work_cycles].order(:id).last
    db[:work_cycles].where(id: worker_review.fetch(:id)).update(completed_at: Time.now)

    manager_output = service_class.call(task_id: task_id)
    manager_review = db[:work_cycles].order(:id).last

    expect(first_implementation_output).to eq("AutoImplementCycle #{first_implementation.fetch(:id)}")
    expect(first_review_output).to eq("AutoImplementCycle #{first_review.fetch(:id)}")
    expect(second_implementation_output).to eq(
      "Step 1 accepted.\nAutoImplementCycle #{second_implementation.fetch(:id)}"
    )
    expect(second_review_output).to eq("AutoImplementCycle #{second_review.fetch(:id)}")
    expect(super_review_output).to eq(
      "Step 2 accepted.\nAutoImplementCycle #{super_review.fetch(:id)}"
    )
    expect(first_review_context).to include('scope' => 'step_review', 'step_number' => 1)
    expect(second_review_context).to include('scope' => 'step_review', 'step_number' => 2)
    expect(worker_review_output).to eq("AutoImplementCycle #{worker_review.fetch(:id)}")
    expect(manager_output).to eq("AutoImplementCycle #{manager_review.fetch(:id)}")
    expect(db[:work_cycles].order(:id).select_map(%i[role action step_number])).to eq(
      [
        ['worker', 'implementation', 1],
        ['reviewer', 'review', nil],
        ['worker', 'implementation', 2],
        ['reviewer', 'review', nil],
        ['reviewer', 'review', nil],
        ['worker', 'review', nil],
        ['manager', 'review', nil],
      ]
    )
    expect(db[:tasks].where(id: task_id).get(:state)).to eq('manager_review')
  end

  it 'starts the next authored step after a clean Reviewer pass' do
    insert_implementation(completed_at: Time.now)
    insert_review(completed_at: Time.now)

    output = service_class.call(task_id: task_id)
    next_implementation = db[:work_cycles].order(:id).last

    expect(output).to eq("Step 1 accepted.\nAutoImplementCycle #{next_implementation.fetch(:id)}")
    expect(next_implementation).to include(
      step_number: 2,
      role: 'worker',
      action: 'implementation',
      completed_at: nil
    )
  end

  it 'starts the next authored step after a skipped-only Reviewer pass' do
    insert_implementation(completed_at: Time.now)
    review_work_cycle_id = insert_review(completed_at: Time.now)
    insert_produced_issue(review_work_cycle_id, decision: 'skipped')

    output = service_class.call(task_id: task_id)
    next_implementation = db[:work_cycles].order(:id).last

    expect(output).to eq("Step 1 accepted.\nAutoImplementCycle #{next_implementation.fetch(:id)}")
    expect(next_implementation.fetch(:step_number)).to eq(2)
  end

  it 'starts one super-review after the last authored step is accepted' do
    File.write(File.join(task_path, 'steps.md'), "# Steps\n\n## Step 1: First\n")
    insert_implementation(completed_at: Time.now)
    insert_review(completed_at: Time.now)

    output = service_class.call(task_id: task_id)
    super_review_work_cycle = db[:work_cycles].order(:id).last

    expect(output).to eq(
      "Step 1 accepted.\nAutoImplementCycle #{super_review_work_cycle.fetch(:id)}"
    )
    expect(super_review_work_cycle).to include(
      role: 'reviewer',
      action: 'review',
      step_number: nil,
      completed_at: nil
    )
    expect(db[:tasks].where(id: task_id).get(:state)).to eq('super_review')
    expect(db[:work_cycles].count).to eq(3)
  end

  it 'starts final Worker review exactly once after a clean super-review' do
    File.write(File.join(task_path, 'steps.md'), "# Steps\n\n## Step 1: First\n")
    insert_implementation(completed_at: Time.now)
    insert_review(completed_at: Time.now)
    service_class.call(task_id: task_id)
    super_review_work_cycle = db[:work_cycles].order(:id).last
    db[:work_cycles].where(id: super_review_work_cycle.fetch(:id)).update(completed_at: Time.now)

    output = service_class.call(task_id: task_id)
    worker_review = db[:work_cycles].order(:id).last

    expect(output).to eq("AutoImplementCycle #{worker_review.fetch(:id)}")
    expect(db[:tasks].where(id: task_id).get(:state)).to eq('worker_final_review')
    expect(worker_review).to include(role: 'worker', action: 'review', completed_at: nil)
    allow(ValidateCleanGitState).to receive(:call).and_raise('should not run')
    expect(service_class.call(task_id: task_id)).to eq("WaitWorkCycle #{worker_review.fetch(:id)}")
    expect(db[:work_cycles].where(role: 'worker', action: 'review').count).to eq(1)
  end

  it 'starts one final Worker self-review after the super-review loop' do
    db[:tasks].where(id: task_id).update(state: 'worker_final_review')
    insert_implementation(completed_at: Time.now)
    insert_review(completed_at: Time.now)

    output = service_class.call(task_id: task_id)
    worker_review = db[:work_cycles].order(:id).last

    expect(output).to eq("AutoImplementCycle #{worker_review.fetch(:id)}")
    expect(worker_review).to include(
      role: 'worker',
      action: 'review',
      step_number: nil,
      completed_at: nil
    )
  end

  it 'starts one Manager review after a clean final Worker self-review' do
    db[:tasks].where(id: task_id).update(state: 'worker_final_review')
    insert_implementation(completed_at: Time.now)
    insert_review(completed_at: Time.now)
    insert_worker_review(completed_at: Time.now)

    output = service_class.call(task_id: task_id)
    manager_review = db[:work_cycles].order(:id).last

    expect(output).to eq("AutoImplementCycle #{manager_review.fetch(:id)}")
    expect(manager_review).to include(role: 'manager', action: 'review', completed_at: nil)
    expect(db[:tasks].where(id: task_id).get(:state)).to eq('manager_review')
    allow(ValidateCleanGitState).to receive(:call).and_raise('should not run')
    expect(service_class.call(task_id: task_id)).to eq("WaitWorkCycle #{manager_review.fetch(:id)}")
    expect(db[:work_cycles].where(role: 'worker', action: 'review').count).to eq(1)
  end

  it 'batches only approved Manager findings into one whole-task correction' do
    db[:tasks].where(id: task_id).update(state: 'manager_review')
    manager_review_id = insert_manager_review(completed_at: Time.now)
    approved_issue_id = insert_produced_issue(
      manager_review_id,
      body: 'Fix the Manager finding.',
      decision: 'approved',
      source: 'manager'
    )
    insert_produced_issue(
      manager_review_id,
      body: 'Leave this unchanged.',
      decision: 'skipped',
      source: 'manager'
    )

    output = service_class.call(task_id: task_id)
    correction = db[:work_cycles].order(:id).last

    expect(output).to eq("AutoImplementCycle #{correction.fetch(:id)}")
    expect(correction).to include(step_number: nil, role: 'worker', action: 'implementation')
    expect(db[:work_cycle_inputs].where(work_cycle_id: correction.fetch(:id)).
      select_map(:reported_issue_id)).to eq([approved_issue_id])
  end

  it 'starts scoped Reviewer review after a completed Manager correction' do
    db[:tasks].where(id: task_id).update(state: 'manager_review')
    manager_review_id = insert_manager_review(completed_at: Time.now)
    issue_id = insert_produced_issue(
      manager_review_id,
      decision: 'approved',
      source: 'manager'
    )
    correction_id = insert_implementation(completed_at: Time.now, step_number: nil)
    db[:work_cycle_inputs].insert(
      created_at: Time.now,
      work_cycle_id: correction_id,
      reported_issue_id: issue_id
    )

    output = service_class.call(task_id: task_id)
    scoped_review = db[:work_cycles].order(:id).last

    expect(output).to eq("AutoImplementCycle #{scoped_review.fetch(:id)}")
    expect(scoped_review).to include(role: 'reviewer', action: 'review', completed_at: nil)
    expect(db[:work_cycle_inputs].where(work_cycle_id: scoped_review.fetch(:id)).
      select_map(:reported_issue_id)).to eq([issue_id])
  end

  it 'starts a fresh Manager review after a skipped-only scoped correction review' do
    db[:tasks].where(id: task_id).update(state: 'manager_review')
    insert_review(completed_at: Time.now)
    insert_worker_review(completed_at: Time.now)
    manager_review_id = insert_manager_review(completed_at: Time.now)
    issue_id = insert_produced_issue(
      manager_review_id,
      decision: 'approved',
      source: 'manager'
    )
    correction_id = insert_implementation(completed_at: Time.now, step_number: nil)
    db[:work_cycle_inputs].insert(
      created_at: Time.now,
      work_cycle_id: correction_id,
      reported_issue_id: issue_id
    )
    scoped_review_id = insert_review(completed_at: Time.now)
    insert_produced_issue(scoped_review_id, decision: 'skipped')

    output = service_class.call(task_id: task_id)
    fresh_manager_review = db[:work_cycles].order(:id).last

    expect(output).to eq("AutoImplementCycle #{fresh_manager_review.fetch(:id)}")
    expect(fresh_manager_review).to include(role: 'manager', action: 'review', completed_at: nil)
    expect(db[:work_cycles].where(role: 'manager', action: 'review').count).to eq(2)
    expect(db[:work_cycles].where(role: 'worker', action: 'review').count).to eq(1)
    expect(db[:work_cycles].where(role: 'reviewer', action: 'review').count).to eq(2)
  end

  it 'repeats scoped corrections before starting a fresh Manager review and final checks' do
    db[:tasks].where(id: task_id).update(state: 'manager_review')
    insert_review(completed_at: Time.now)
    insert_worker_review(completed_at: Time.now)
    manager_review_id = insert_manager_review(completed_at: Time.now)
    manager_issue_id = insert_produced_issue(
      manager_review_id,
      decision: 'approved',
      source: 'manager'
    )
    first_correction_id = insert_implementation(completed_at: Time.now, step_number: nil)
    db[:work_cycle_inputs].insert(
      created_at: Time.now,
      work_cycle_id: first_correction_id,
      reported_issue_id: manager_issue_id
    )
    scoped_review_id = insert_review(completed_at: Time.now)
    approved_scoped_issue_id = insert_produced_issue(
      scoped_review_id,
      body: 'Fix the correction defect.',
      decision: 'approved'
    )
    insert_produced_issue(
      scoped_review_id,
      body: 'Skip this correction concern.',
      decision: 'skipped'
    )

    correction_output = service_class.call(task_id: task_id)
    second_correction = db[:work_cycles].order(:id).last
    db[:work_cycles].where(id: second_correction.fetch(:id)).update(completed_at: Time.now)
    scoped_output = service_class.call(task_id: task_id)
    second_scoped_review = db[:work_cycles].order(:id).last
    db[:work_cycles].where(id: second_scoped_review.fetch(:id)).update(completed_at: Time.now)
    manager_output = service_class.call(task_id: task_id)
    fresh_manager_review = db[:work_cycles].order(:id).last
    db[:work_cycles].where(id: fresh_manager_review.fetch(:id)).update(completed_at: Time.now)
    allow(RunTaskFinalChecks).to receive(:call).and_return('Task completed output.')

    expect(service_class.call(task_id: task_id)).to eq('Task completed output.')
    expect(correction_output).to eq("AutoImplementCycle #{second_correction.fetch(:id)}")
    expect(db[:work_cycle_inputs].where(work_cycle_id: second_correction.fetch(:id)).
      select_map(:reported_issue_id)).to eq([approved_scoped_issue_id])
    expect(scoped_output).to eq("AutoImplementCycle #{second_scoped_review.fetch(:id)}")
    expect(manager_output).to eq("AutoImplementCycle #{fresh_manager_review.fetch(:id)}")
    expect(RunTaskFinalChecks).to have_received(:call).with(task_id: task_id).once
    expect(db[:work_cycles].where(role: 'manager', action: 'review').count).to eq(2)
    expect(db[:work_cycles].where(role: 'worker', action: 'review').count).to eq(1)
  end

  it 'creates a whole-task correction for approved final Worker findings' do
    db[:tasks].where(id: task_id).update(state: 'worker_final_review')
    insert_implementation(completed_at: Time.now)
    insert_review(completed_at: Time.now)
    worker_review_id = insert_worker_review(completed_at: Time.now)
    issue_id = insert_produced_issue(
      worker_review_id,
      body: 'Fix the final Worker finding.',
      decision: 'approved',
      source: 'worker'
    )

    output = service_class.call(task_id: task_id)
    correction = db[:work_cycles].order(:id).last

    expect(output).to eq("AutoImplementCycle #{correction.fetch(:id)}")
    expect(correction).to include(step_number: nil, role: 'worker', action: 'implementation')
    expect(db[:work_cycle_inputs].where(work_cycle_id: correction.fetch(:id)).
      select_map(:reported_issue_id)).to eq([issue_id])
  end

  it 'starts Manager review after settling a scoped final Worker correction' do
    db[:tasks].where(id: task_id).update(state: 'worker_final_review')
    insert_implementation(completed_at: Time.now)
    insert_review(completed_at: Time.now)
    worker_review_id = insert_worker_review(completed_at: Time.now)
    issue_id = insert_produced_issue(
      worker_review_id,
      decision: 'approved',
      source: 'worker'
    )
    correction_id = insert_implementation(completed_at: Time.now, step_number: nil)
    db[:work_cycle_inputs].insert(
      created_at: Time.now,
      work_cycle_id: correction_id,
      reported_issue_id: issue_id
    )
    insert_review(completed_at: Time.now)

    output = service_class.call(task_id: task_id)
    manager_review = db[:work_cycles].order(:id).last

    expect(output).to eq("AutoImplementCycle #{manager_review.fetch(:id)}")
    expect(db[:tasks].where(id: task_id).get(:state)).to eq('manager_review')
    expect(manager_review).to include(role: 'manager', action: 'review')
    expect(db[:work_cycles].where(role: 'worker', action: 'review').count).to eq(1)
  end

  it 'runs final checks after a clean Manager review' do
    db[:tasks].where(id: task_id).update(state: 'manager_review')
    insert_manager_review(completed_at: Time.now)
    allow(RunTaskFinalChecks).to receive(:call).and_return('Task completed output.')

    expect(service_class.call(task_id: task_id)).to eq('Task completed output.')
    expect(RunTaskFinalChecks).to have_received(:call).with(task_id: task_id)
  end

  it 'runs final checks after every Manager concern is skipped' do
    db[:tasks].where(id: task_id).update(state: 'manager_review')
    manager_review_id = insert_manager_review(completed_at: Time.now)
    insert_produced_issue(manager_review_id, decision: 'skipped', source: 'manager')
    allow(RunTaskFinalChecks).to receive(:call).and_return('Task completed output.')

    expect(service_class.call(task_id: task_id)).to eq('Task completed output.')
    expect(RunTaskFinalChecks).to have_received(:call).with(task_id: task_id)
    expect(db[:work_cycles].where(role: 'manager', action: 'review').count).to eq(1)
  end

  it 'reruns failed final checks without creating another Manager review' do
    db[:tasks].where(id: task_id).update(state: 'manager_review')
    insert_manager_review(completed_at: Time.now)
    allow(RunTaskFinalChecks).to receive(:call).and_return('Final checks failed.')

    expect(service_class.call(task_id: task_id)).to eq('Final checks failed.')
    expect(service_class.call(task_id: task_id)).to eq('Final checks failed.')
    expect(RunTaskFinalChecks).to have_received(:call).with(task_id: task_id).twice
    expect(db[:work_cycles].where(role: 'manager', action: 'review').count).to eq(1)
  end

  it 'returns durable completion without rerunning checks or checking Git' do
    db[:tasks].where(id: task_id).update(state: 'final_checks_passed')
    allow(RunTaskFinalChecks).to receive(:call).and_raise('should not run')
    allow(ValidateCleanGitState).to receive(:call).and_raise('should not run')

    expected_output = "Task #{task_id} completed locally.\nPush: not performed."

    expect(service_class.call(task_id: task_id)).to eq(expected_output)
    expect(service_class.call(task_id: task_id)).to eq(expected_output)
    expect(db[:work_cycles].count).to eq(0)
  end

  it 'creates one whole-task correction for approved super-review issues' do
    db[:tasks].where(id: task_id).update(state: 'super_review')
    insert_implementation(completed_at: Time.now)
    review_work_cycle_id = insert_review(completed_at: Time.now)
    approved_issue_ids = [
      insert_produced_issue(review_work_cycle_id, body: 'First final fix.', decision: 'approved'),
      insert_produced_issue(review_work_cycle_id, body: 'Second final fix.', decision: 'approved'),
    ]

    output = service_class.call(task_id: task_id)
    correction = db[:work_cycles].order(:id).last

    expect(output).to eq("AutoImplementCycle #{correction.fetch(:id)}")
    expect(correction).to include(step_number: nil, role: 'worker', action: 'implementation')
    expect(db[:work_cycle_inputs].where(work_cycle_id: correction.fetch(:id)).order(:id).
      select_map(:reported_issue_id)).to eq(approved_issue_ids)
  end

  it 'settles a clean scoped super-review correction without rerunning super-review' do
    db[:tasks].where(id: task_id).update(state: 'super_review')
    insert_implementation(completed_at: Time.now)
    super_review_work_cycle_id = insert_review(completed_at: Time.now)
    issue_id = insert_produced_issue(super_review_work_cycle_id, decision: 'approved')
    correction_id = insert_implementation(completed_at: Time.now, step_number: nil)
    db[:work_cycle_inputs].insert(
      created_at: Time.now,
      work_cycle_id: correction_id,
      reported_issue_id: issue_id
    )
    insert_review(completed_at: Time.now)

    output = service_class.call(task_id: task_id)
    worker_review = db[:work_cycles].order(:id).last

    expect(output).to eq("AutoImplementCycle #{worker_review.fetch(:id)}")
    expect(db[:tasks].where(id: task_id).get(:state)).to eq('worker_final_review')
    expect(worker_review).to include(role: 'worker', action: 'review')
    expect(db[:work_cycles].where(role: 'reviewer', action: 'review').count).to eq(2)
  end

  it 'creates one correction with every approved issue after the pass is settled' do
    insert_implementation(completed_at: Time.now)
    review_work_cycle_id = insert_review(completed_at: Time.now)
    approved_issue_ids = [
      insert_produced_issue(review_work_cycle_id, body: 'First fix.', decision: 'approved'),
      insert_produced_issue(review_work_cycle_id, body: 'Second fix.', decision: 'approved'),
    ]
    insert_produced_issue(review_work_cycle_id, body: 'Skipped issue.', decision: 'skipped')

    output = service_class.call(task_id: task_id)
    correction = db[:work_cycles].order(:id).last

    expect(output).to eq("AutoImplementCycle #{correction.fetch(:id)}")
    expect(correction).to include(step_number: 1, role: 'worker', action: 'implementation')
    expect(db[:work_cycle_inputs].where(work_cycle_id: correction.fetch(:id)).order(:id).
      select_map(:reported_issue_id)).to eq(approved_issue_ids)
  end

  def insert_implementation(completed_at: nil, step_number: 1)
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

  def insert_produced_issue(work_cycle_id, body: 'Review issue.', decision: nil, source: 'reviewer')
    issue_id = StoreIssue.call(project_path: '/project', source: source, body: body)
    db[:reported_issues].where(id: issue_id).update(
      decision: decision,
      decision_reason: decision && "#{decision.capitalize} in spec."
    )
    db[:work_cycle_reported_issues].insert(
      created_at: Time.now,
      work_cycle_id: work_cycle_id,
      reported_issue_id: issue_id
    )
    issue_id
  end
end
