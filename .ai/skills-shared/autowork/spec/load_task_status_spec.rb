# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'tmpdir'
require_relative 'spec_helper'

RSpec.describe 'LoadTaskStatus' do
  let(:service_class) { Object.const_get(:LoadTaskStatus) }
  let(:db) { Database.connection }
  let(:root_path) { Dir.mktmpdir('load-task-status-spec') }
  let(:task_path) { File.join(root_path, 'env', '0038-render-status') }

  before do
    write_task_files
  end

  after do
    FileUtils.remove_entry(root_path)
  end

  it 'loads authored identity with not-started workflow state' do
    expect(load_status).to include(
      task_id: '0038',
      task_path: File.realpath(task_path),
      project: 'env',
      branch: 'main',
      task: nil,
      autoimplement: {
        state: nil,
        accepted_step_count: 0,
        total_step_count: 2,
        pending: nil
      },
      autofix: nil,
      next_action: '/autoimplement'
    )
  end

  it 'loads an initialized Task with no accepted steps' do
    insert_task

    expect(load_status.fetch(:autoimplement)).to eq(
      state: 'initialized',
      accepted_step_count: 0,
      total_step_count: 2,
      pending: nil
    )
    expect(load_status.fetch(:next_action)).to eq('/autoimplement')
  end

  it 'counts only accepted authored steps' do
    task_id = insert_task
    insert_implementation(task_id: task_id, step_number: 1)
    insert_review(task_id: task_id)
    insert_implementation(task_id: task_id, step_number: 2)
    insert_review(task_id: task_id, issue_decisions: ['approved'])

    expect(load_status.fetch(:autoimplement)).to include(
      accepted_step_count: 1,
      total_step_count: 2
    )
  end

  it 'loads the one incomplete Task Work Cycle first' do
    task_id = insert_task
    work_cycle_id = insert_implementation(task_id: task_id, step_number: 1, completed_at: nil)

    expect(load_status.fetch(:autoimplement).fetch(:pending)).to eq(
      type: 'work_cycle', id: work_cycle_id
    )
    expect(load_status.fetch(:next_action)).to eq("WaitWorkCycle #{work_cycle_id}")
  end

  it 'loads the first undecided issue produced by a Task Work Cycle' do
    task_id = insert_task
    work_cycle_id = insert_review(task_id: task_id, issue_decisions: [nil])
    issue_id = db[:work_cycle_reported_issues].where(work_cycle_id: work_cycle_id).get(:reported_issue_id)

    expect(load_status.fetch(:autoimplement).fetch(:pending)).to eq(type: 'issue', id: issue_id)
    expect(load_status.fetch(:next_action)).to eq("Issue: #{issue_id}")
  end

  %w[super_review worker_final_review manager_review].each do |state|
    it "loads the #{state} lifecycle phase" do
      insert_task(state: state)

      expect(load_status.fetch(:autoimplement).fetch(:state)).to eq(state)
      expect(load_status.fetch(:next_action)).to eq('/autoimplement')
    end
  end

  it 'loads terminal local completion with no next action' do
    insert_task(state: 'final_checks_passed')

    expect(load_status.fetch(:autoimplement)).to include(state: 'final_checks_passed', pending: nil)
    expect(load_status.fetch(:next_action)).to eq('None')
  end

  it 'loads no Autofix Review for a completed Task without Reviews' do
    insert_task(state: 'final_checks_passed')

    expect(load_status.fetch(:autofix)).to be_nil
    expect(load_status.fetch(:next_action)).to eq('None')
  end

  it 'loads an active Autofix Review with its incomplete Work Cycle' do
    task_id = insert_task(state: 'final_checks_passed')
    review_id = insert_autofix_review(task_id: task_id, number: 1)
    work_cycle_id = insert_review_work_cycle(review_id: review_id)

    expect(load_status.fetch(:autofix)).to eq(
      number: 1,
      source: 'local',
      state: 'manager_issues_assessment',
      pending: { type: 'work_cycle', id: work_cycle_id }
    )
    expect(load_status.fetch(:next_action)).to eq("WaitWorkCycle #{work_cycle_id}")
  end

  it 'loads an active Autofix Review with its first undecided Review issue' do
    task_id = insert_task(state: 'final_checks_passed')
    review_id = insert_autofix_review(task_id: task_id, number: 1)
    issue_id = insert_review_issue(review_id: review_id)

    expect(load_status.fetch(:autofix).fetch(:pending)).to eq(type: 'issue', id: issue_id)
    expect(load_status.fetch(:next_action)).to eq("Issue: #{issue_id}")
  end

  it 'loads a resumable active Autofix Review with no pending item' do
    task_id = insert_task(state: 'final_checks_passed')
    insert_autofix_review(task_id: task_id, number: 1, state: 'manager_review')

    expect(load_status.fetch(:autofix)).to include(number: 1, state: 'manager_review', pending: nil)
    expect(load_status.fetch(:next_action)).to eq('/autofix')
  end

  it 'loads only the highest-numbered completed Autofix Review' do
    task_id = insert_task(state: 'final_checks_passed')
    insert_autofix_review(task_id: task_id, number: 1, state: 'completed')
    insert_autofix_review(task_id: task_id, number: 2, state: 'completed', source: 'github')

    expect(load_status.fetch(:autofix)).to eq(
      number: 2,
      source: 'github',
      state: 'completed',
      pending: nil
    )
    expect(load_status.fetch(:next_action)).to eq('None')
  end

  it 'rejects multiple incomplete Task Work Cycles' do
    task_id = insert_task
    insert_implementation(task_id: task_id, step_number: 1, completed_at: nil)
    insert_implementation(task_id: task_id, step_number: 2, completed_at: nil)

    expect { load_status }.to raise_error(/multiple incomplete Work Cycles/)
  end

  def load_status
    service_class.call(connection: db, task_path: task_path)
  end

  def insert_task(state: 'initialized')
    db[:tasks].insert(
      created_at: Time.now,
      task_path: File.realpath(task_path),
      project_path: '/checkout',
      starting_commit_sha: 'starting-sha',
      state: state
    )
  end

  def insert_implementation(task_id:, step_number:, completed_at: Time.now)
    db[:work_cycles].insert(
      created_at: Time.now,
      completed_at: completed_at,
      task_id: task_id,
      step_number: step_number,
      role: 'worker',
      action: 'implementation'
    )
  end

  def insert_review(task_id:, issue_decisions: [])
    work_cycle_id = db[:work_cycles].insert(
      created_at: Time.now,
      completed_at: Time.now,
      task_id: task_id,
      role: 'reviewer',
      action: 'review'
    )
    issue_decisions.each do |decision|
      issue_id = StoreIssue.call(project_path: '/checkout', source: 'reviewer', body: 'Review issue.')
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

  def insert_autofix_review(task_id:, number:, state: 'manager_issues_assessment', source: 'local')
    db[:reviews].insert(
      created_at: Time.now,
      completed_at: state == 'completed' ? Time.now : nil,
      number: number,
      source: source,
      starting_commit_sha: 'review-starting-sha',
      state: state,
      task_id: task_id
    )
  end

  def insert_review_work_cycle(review_id:)
    db[:work_cycles].insert(
      created_at: Time.now,
      completed_at: nil,
      review_id: review_id,
      role: 'worker',
      action: 'implementation'
    )
  end

  def insert_review_issue(review_id:)
    issue_id = StoreIssue.call(project_path: '/checkout', source: 'local', body: 'Autofix issue.')
    db[:review_issues].insert(
      created_at: Time.now,
      review_id: review_id,
      reported_issue_id: issue_id
    )
    issue_id
  end

  def write_task_files
    FileUtils.mkdir_p(task_path)
    File.write(File.join(task_path, 'task.md'), "# Context\n")
    File.write(File.join(task_path, 'steps.md'), "# Steps\n\n## Step 1: One\n\n## Step 2: Two\n")
    File.write(
      File.join(task_path, 'config.json'),
      JSON.generate(
        'branch' => {
          'name' => 'main',
          'original_base_ref' => 'base-sha',
          'original_base_commit_sha' => 'base-sha',
          'active_base_ref' => 'base-sha',
          'active_base_commit_sha' => 'base-sha'
        }
      )
    )
  end
end
