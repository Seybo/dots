# frozen_string_literal: true

require 'fileutils'
require 'open3'
require 'tmpdir'
require_relative 'spec_helper'

RSpec.describe 'Manager review flow' do
  let(:db) { Database.connection }
  let(:project_path) { Dir.mktmpdir('autofix-manager-flow-spec') }

  before do
    git!('init', '-q')
    git!('config', 'user.email', 'autofix@example.com')
    git!('config', 'user.name', 'Autofix')
    File.write(File.join(project_path, 'tracked.txt'), "initial\n")
    git!('add', 'tracked.txt')
    git!('commit', '-q', '-m', 'Initial commit')
  end

  after do
    FileUtils.remove_entry(project_path)
  end

  it 'finalizes directly when every Manager issue is skipped' do
    review_id, manager_work_cycle_id, manager_issue_id = complete_manager_review_with_issue

    output = HandleDecision.call(issue_id: manager_issue_id, decision: 'skipped')
    review = db[:reviews].where(id: review_id).first

    expect(output).to include(
      'Final checks:',
      'Skipped: no Gemfile.',
      'Review 1 completed locally.',
      'Push: not performed.'
    )
    expect(review).to include(state: 'completed', completed_at: be_a(Time))
    expect(db[:work_cycles].where(role: 'manager', action: 'review').select_map(:id)).
      to eq([manager_work_cycle_id])
    expect(git!('log', '-1', '--format=%s').strip).to eq('Review 1')
  end

  it 'implements an approved Manager issue and returns through fresh Reviewer and Manager review' do
    review_id, first_manager_work_cycle_id, manager_issue_id = complete_manager_review_with_issue

    output = HandleDecision.call(issue_id: manager_issue_id, decision: 'approved')
    implementation_work_cycle = db[:work_cycles].order(:id).last

    expect(output).to eq(
      "Decision: approved\n\nAutoFixCycle #{implementation_work_cycle.fetch(:id)}\nAutoFixRole worker"
    )
    File.write(File.join(project_path, 'tracked.txt'), "corrected\n")
    git!('add', 'tracked.txt')
    git!('commit', '-q', '-m', "Work cycle #{implementation_work_cycle.fetch(:id)}")
    StoreWorkCycleCompletion.call(
      work_cycle_id: implementation_work_cycle.fetch(:id),
      work_cycle_result: implementation_result(implementation_work_cycle.fetch(:id))
    )
    reviewer_work_cycle_id = StartReviewerReviewWorkCycle.call(review_id: review_id)
    StoreWorkCycleCompletion.call(
      work_cycle_id: reviewer_work_cycle_id,
      work_cycle_result: review_result(reviewer_work_cycle_id, role: 'reviewer', reported_issues: [])
    )

    manager_output = ResumeReview.call(project_path: project_path, branch_name: 'feature')
    second_manager_work_cycle = db[:work_cycles].order(:id).last

    expect(manager_output).to eq(
      "AutoFixCycle #{second_manager_work_cycle.fetch(:id)}\nAutoFixRole manager"
    )
    expect(second_manager_work_cycle).to include(role: 'manager', action: 'review')
    expect(first_manager_work_cycle_id).to be < second_manager_work_cycle.fetch(:id)
    expect(db[:work_cycles].where(role: 'worker', action: 'review').count).to eq(1)
    expect(db[:work_cycle_inputs].where(work_cycle_id: second_manager_work_cycle.fetch(:id)).
      order(:reported_issue_id).select_map(:reported_issue_id)).to eq(
        db[:review_issues].where(review_id: review_id).order(:reported_issue_id).
          select_map(:reported_issue_id)
      )
    expect(db[:reported_issues].where(id: manager_issue_id).get(:decision)).to eq('approved')
  end

  private

  def complete_manager_review_with_issue
    review_id = StoreReview.call(
      project_path: project_path,
      source: 'local',
      branch_name: 'feature',
      base_ref: 'origin/main',
      base_commit_sha: 'base-sha',
      issue_data: [{ source_id: nil, body: 'Original issue.' }]
    )
    original_issue_id = db[:review_issues].where(review_id: review_id).get(:reported_issue_id)
    db[:reported_issues].where(id: original_issue_id).update(decision: 'approved')
    implementation_work_cycle_id = StartImplementationWorkCycle.call(review_id: review_id)
    File.write(File.join(project_path, 'tracked.txt'), "implemented\n")
    git!('add', 'tracked.txt')
    git!('commit', '-q', '-m', "Work cycle #{implementation_work_cycle_id}")
    StoreWorkCycleCompletion.call(
      work_cycle_id: implementation_work_cycle_id,
      work_cycle_result: implementation_result(implementation_work_cycle_id)
    )
    reviewer_work_cycle_id = StartReviewerReviewWorkCycle.call(review_id: review_id)
    StoreWorkCycleCompletion.call(
      work_cycle_id: reviewer_work_cycle_id,
      work_cycle_result: review_result(reviewer_work_cycle_id, role: 'reviewer', reported_issues: [])
    )
    worker_work_cycle_id = StartWorkerReviewWorkCycle.call(review_id: review_id)
    StoreWorkCycleCompletion.call(
      work_cycle_id: worker_work_cycle_id,
      work_cycle_result: review_result(worker_work_cycle_id, role: 'worker', reported_issues: [])
    )
    manager_work_cycle_id = StartManagerReviewWorkCycle.call(review_id: review_id)
    StoreWorkCycleCompletion.call(
      work_cycle_id: manager_work_cycle_id,
      work_cycle_result: review_result(
        manager_work_cycle_id,
        role: 'manager',
        reported_issues: ['Manager-reported issue.']
      )
    )
    manager_issue_id = db[:reported_issues].where(source: 'manager').get(:id)

    [review_id, manager_work_cycle_id, manager_issue_id]
  end

  def implementation_result(work_cycle_id)
    {
      'work_cycle_id' => work_cycle_id,
      'role' => 'worker',
      'action' => 'implementation',
      'status' => 'completed',
      'provider' => nil,
      'model' => nil,
      'reasoning_level' => nil
    }
  end

  def review_result(work_cycle_id, role:, reported_issues:)
    implementation_result(work_cycle_id).merge(
      'role' => role,
      'action' => 'review',
      'reported_issues' => reported_issues
    )
  end

  def git!(*arguments)
    stdout, stderr, status = Open3.capture3('git', '-C', project_path, *arguments)
    raise stderr unless status.success?

    stdout
  end
end
