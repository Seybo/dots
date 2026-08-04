# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'open3'
require 'tmpdir'
require_relative '../../spec/spec_helper'

RSpec.describe ShowWorkCycle do
  let(:db) { Database.connection }
  let(:project_path) { Dir.mktmpdir('autofix-show-work-cycle-spec') }

  before do
    allow(Database).to receive(:readonly_connection).and_return(db)
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

  it 'returns source-neutral Work Cycle and Review context as JSON' do
    review_id = StoreReview.call(
      project_path: project_path,
      source: 'local',
      branch_name: 'feature',
      base_ref: 'origin/main',
      base_commit_sha: 'base-sha',
      issue_data: [{ source_id: nil, body: 'Approved issue.' }]
    )
    issue_id = db[:review_issues].where(review_id: review_id).get(:reported_issue_id)
    db[:reported_issues].where(id: issue_id).update(decision: 'approved')
    work_cycle_id = StartImplementationWorkCycle.call(review_id: review_id)

    context = JSON.parse(described_class.call(work_cycle_id: work_cycle_id))

    expect(context).to eq(
      'work_cycle_id' => work_cycle_id,
      'review_id' => review_id,
      'review_number' => 1,
      'role' => 'worker',
      'action' => 'implementation',
      'project_path' => project_path,
      'branch_name' => 'feature',
      'starting_commit_sha' => git!('rev-parse', 'HEAD').strip,
      'active_base_ref' => 'origin/main',
      'active_base_commit_sha' => 'base-sha',
      'inputs' => [
        {
          'id' => issue_id,
          'source' => 'local',
          'body' => 'Approved issue.',
          'decision' => 'approved'
        },
      ],
      'reported_issues' => []
    )
  end

  it 'returns Reviewer context without an interim commit SHA' do
    _review_id, issue_id, _implementation_work_cycle_id, reviewer_work_cycle_id = start_review_sequence

    context = JSON.parse(described_class.call(work_cycle_id: reviewer_work_cycle_id))

    expect(context).to include(
      'role' => 'reviewer',
      'action' => 'review',
      'inputs' => [
        {
          'id' => issue_id,
          'source' => 'local',
          'body' => 'Original issue.',
          'decision' => 'approved'
        },
      ],
      'reported_issues' => []
    )
    expect(context.keys).not_to include('result')
  end

  it 'returns final Worker context without the Reviewer result or an interim commit SHA' do
    review_id, issue_id, _implementation_work_cycle_id, reviewer_work_cycle_id = start_review_sequence
    db[:work_cycles].where(id: reviewer_work_cycle_id).update(
      completed_at: Time.now
    )
    db[:reviews].where(id: review_id).update(state: 'worker_review')
    worker_work_cycle_id = StartWorkerReviewWorkCycle.call(review_id: review_id)

    context = JSON.parse(described_class.call(work_cycle_id: worker_work_cycle_id))

    expect(context).to include(
      'role' => 'worker',
      'action' => 'review',
      'inputs' => [
        {
          'id' => issue_id,
          'source' => 'local',
          'body' => 'Original issue.',
          'decision' => 'approved'
        },
      ],
      'reported_issues' => []
    )
    expect(context.keys).not_to include('result')
  end

  it 'returns original inputs and review-reported issues' do
    _review_id, issue_id, _implementation_work_cycle_id, reviewer_work_cycle_id = start_review_sequence
    StoreWorkCycleCompletion.call(
      work_cycle_id: reviewer_work_cycle_id,
      work_cycle_result: {
        'work_cycle_id' => reviewer_work_cycle_id,
        'role' => 'reviewer',
        'action' => 'review',
        'status' => 'completed',
        'provider' => 'openai-codex',
        'model' => 'gpt-5.6-sol',
        'reasoning_level' => 'high',
        'reported_issues' => ['Review-reported issue.']
      }
    )
    reported_issue_id = db[:work_cycle_reported_issues].where(work_cycle_id: reviewer_work_cycle_id).
                        get(:reported_issue_id)

    context = JSON.parse(described_class.call(work_cycle_id: reviewer_work_cycle_id))

    expect(context).to include(
      'inputs' => [
        {
          'id' => issue_id,
          'source' => 'local',
          'body' => 'Original issue.',
          'decision' => 'approved'
        },
      ],
      'reported_issues' => [
        {
          'id' => reported_issue_id,
          'source' => 'reviewer',
          'body' => 'Review-reported issue.',
          'decision' => nil
        },
      ]
    )
  end

  it 'returns every issue and decision for a Manager review' do
    review_id = StoreReview.call(
      project_path: project_path,
      source: 'local',
      branch_name: 'feature',
      base_ref: 'origin/main',
      base_commit_sha: 'base-sha',
      issue_data: [
        { source_id: nil, body: 'Approved issue.' },
        { source_id: nil, body: 'Skipped issue.' },
      ]
    )
    issue_ids = db[:review_issues].where(review_id: review_id).order(:id).
                select_map(:reported_issue_id)
    db[:reported_issues].where(id: issue_ids.first).update(decision: 'approved')
    db[:reported_issues].where(id: issue_ids.last).update(decision: 'skipped')
    db[:reviews].where(id: review_id).update(
      state: 'manager_review',
      starting_commit_sha: git!('rev-parse', 'HEAD').strip
    )
    work_cycle_id = StartManagerReviewWorkCycle.call(review_id: review_id)

    context = JSON.parse(described_class.call(work_cycle_id: work_cycle_id))

    expect(context).to include(
      'role' => 'manager',
      'action' => 'review',
      'inputs' => [
        {
          'id' => issue_ids.first,
          'source' => 'local',
          'body' => 'Approved issue.',
          'decision' => 'approved'
        },
        {
          'id' => issue_ids.last,
          'source' => 'local',
          'body' => 'Skipped issue.',
          'decision' => 'skipped'
        },
      ]
    )
  end

  def start_review_sequence
    review_id = StoreReview.call(
      project_path: project_path,
      source: 'local',
      branch_name: 'feature',
      base_ref: 'origin/main',
      base_commit_sha: 'base-sha',
      issue_data: [{ source_id: nil, body: 'Original issue.' }]
    )
    issue_id = db[:review_issues].where(review_id: review_id).get(:reported_issue_id)
    db[:reported_issues].where(id: issue_id).update(decision: 'approved')
    implementation_work_cycle_id = StartImplementationWorkCycle.call(review_id: review_id)
    db[:work_cycles].where(id: implementation_work_cycle_id).update(
      completed_at: Time.now
    )
    db[:reviews].where(id: review_id).update(state: 'reviewer_review')
    reviewer_work_cycle_id = StartReviewerReviewWorkCycle.call(review_id: review_id)

    [review_id, issue_id, implementation_work_cycle_id, reviewer_work_cycle_id]
  end

  def git!(*arguments)
    stdout, stderr, status = Open3.capture3('git', '-C', project_path, *arguments)
    raise stderr unless status.success?

    stdout
  end
end
