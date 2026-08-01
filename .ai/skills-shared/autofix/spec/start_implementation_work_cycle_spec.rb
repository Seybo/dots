# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'open3'
require 'tmpdir'
require_relative 'spec_helper'

RSpec.describe StartImplementationWorkCycle do
  let(:db) { Database.connection }
  let(:project_path) { Dir.mktmpdir('autofix-work-cycle-spec') }

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

  it 'creates one Worker implementation Work Cycle with approved inputs' do
    review_id = store_review(['Approved issue.', 'Skipped issue.'])
    issue_ids = review_issue_ids(review_id)
    db[:reported_issues].where(id: issue_ids.first).update(decision: 'approved')
    db[:reported_issues].where(id: issue_ids.last).update(decision: 'skipped')

    work_cycle_id = described_class.call(review_id: review_id)

    expect(db[:work_cycles].where(id: work_cycle_id).first).to include(
      review_id: review_id,
      role: 'worker',
      action: 'implementation',
      completed_at: nil
    )
    expect(db[:work_cycle_inputs].where(work_cycle_id: work_cycle_id).select_map(:reported_issue_id)).
      to eq([issue_ids.first])
    expect(db[:reviews].where(id: review_id).first).to include(
      state: 'worker_implementation',
      starting_commit_sha: git!('rev-parse', 'HEAD').strip
    )
  end

  it 'creates the same implementation Work Cycle for approved review-reported issues' do
    review_id, _first_implementation_id, _, reported_issue_ids =
      store_reported_issue_sequence(role: 'reviewer', bodies: ['First issue.', 'Skipped issue.', 'Last issue.'])
    db[:reported_issues].where(id: reported_issue_ids.values_at(0, 2)).update(decision: 'approved')
    db[:reported_issues].where(id: reported_issue_ids[1]).update(decision: 'skipped')
    review_before = db[:reviews].where(id: review_id).first

    work_cycle_id = described_class.call(review_id: review_id)

    expect(db[:work_cycles].where(id: work_cycle_id).first).to include(
      review_id: review_id,
      role: 'worker',
      action: 'implementation'
    )
    expect(db[:work_cycle_inputs].where(work_cycle_id: work_cycle_id).order(:id).
      select_map(:reported_issue_id)).to eq(reported_issue_ids.values_at(0, 2))
    expect(db[:reviews].where(id: review_id).first).to include(
      state: 'worker_implementation',
      starting_commit_sha: review_before.fetch(:starting_commit_sha),
      active_base_ref: review_before.fetch(:active_base_ref),
      active_base_commit_sha: review_before.fetch(:active_base_commit_sha)
    )
    expect(db[:review_issues].where(review_id: review_id).count).to eq(4)
  end

  it 'uses the same implementation path for a Worker-reported issue' do
    review_id, _first_implementation_id, _, reported_issue_ids =
      store_reported_issue_sequence(role: 'worker', bodies: ['Worker-reported issue.'])
    db[:reported_issues].where(id: reported_issue_ids).update(decision: 'approved')

    work_cycle_id = described_class.call(review_id: review_id)

    expect(db[:work_cycles].where(id: work_cycle_id).first).
      to include(review_id: review_id, role: 'worker', action: 'implementation')
    expect(db[:work_cycle_inputs].where(work_cycle_id: work_cycle_id).
      select_map(:reported_issue_id)).to eq(reported_issue_ids)
  end

  it 'keeps approved inputs eligible after they were inputs to a review Work Cycle' do
    review_id = store_review(['Approved issue.'])
    issue_id = review_issue_ids(review_id).first
    db[:reported_issues].where(id: issue_id).update(decision: 'approved')
    review_work_cycle_id = insert_work_cycle(review_id: review_id, role: 'worker', action: 'review')
    db[:work_cycle_inputs].insert(
      created_at: Time.now,
      work_cycle_id: review_work_cycle_id,
      reported_issue_id: issue_id
    )

    implementation_work_cycle_id = described_class.call(review_id: review_id)

    expect(db[:work_cycle_inputs].where(work_cycle_id: implementation_work_cycle_id).
      select_map(:reported_issue_id)).to eq([issue_id])
  end

  it 'returns nil without checking Git when no approved undispatched issue exists' do
    review_id = store_review(['Skipped issue.'])
    issue_id = review_issue_ids(review_id).first
    db[:reported_issues].where(id: issue_id).update(decision: 'skipped')
    File.write(File.join(project_path, 'tracked.txt'), "changed\n")

    expect(described_class.call(review_id: review_id)).to be_nil
    expect(db[:work_cycles].count).to eq(0)
    expect(db[:reviews].where(id: review_id).first).to include(
      state: 'manager_issues_assessment',
      starting_commit_sha: nil
    )
  end

  it 'does not dispatch an approved issue twice' do
    review_id = store_review(['Approved issue.'])
    issue_id = review_issue_ids(review_id).first
    db[:reported_issues].where(id: issue_id).update(decision: 'approved')
    work_cycle_id = described_class.call(review_id: review_id)
    db[:reviews].where(id: review_id).update(state: 'manager_issues_assessment')

    expect(described_class.call(review_id: review_id)).to be_nil
    expect(db[:work_cycles].where(review_id: review_id, action: 'implementation').count).to eq(1)
    expect(db[:work_cycle_inputs].where(work_cycle_id: work_cycle_id).
      select_map(:reported_issue_id)).to eq([issue_id])
  end

  it 'leaves the Review unchanged when the working tree is dirty' do
    review_id = store_review(['Approved issue.'])
    issue_id = review_issue_ids(review_id).first
    db[:reported_issues].where(id: issue_id).update(decision: 'approved')
    File.write(File.join(project_path, 'tracked.txt'), "changed\n")

    expect { described_class.call(review_id: review_id) }.
      to raise_error(RuntimeError, /Working tree is not clean/)

    expect(db[:work_cycles].count).to eq(0)
    expect(db[:work_cycle_inputs].count).to eq(0)
    expect(db[:reviews].where(id: review_id).first).to include(
      state: 'manager_issues_assessment',
      starting_commit_sha: nil
    )
  end

  def store_reported_issue_sequence(role:, bodies:)
    review_id = store_review(['Original issue.'])
    original_issue_id = review_issue_ids(review_id).first
    db[:reported_issues].where(id: original_issue_id).update(decision: 'approved')
    implementation_work_cycle_id = described_class.call(review_id: review_id)
    db[:work_cycles].where(id: implementation_work_cycle_id).update(
      completed_at: Time.now
    )
    review_work_cycle_id = insert_work_cycle(
      review_id: review_id,
      role: role,
      action: 'review'
    )
    StoreWorkCycleCompletion.call(
      work_cycle_id: review_work_cycle_id,
      work_cycle_result: {
        'work_cycle_id' => review_work_cycle_id,
        'role' => role,
        'action' => 'review',
        'status' => 'completed',
        'provider' => 'openai-codex',
        'model' => 'gpt-5.6-sol',
        'reasoning_level' => 'high',
        'reported_issues' => bodies
      }
    )
    reported_issue_ids = db[:work_cycle_reported_issues].where(work_cycle_id: review_work_cycle_id).
                         order(:id).select_map(:reported_issue_id)

    [review_id, implementation_work_cycle_id, review_work_cycle_id, reported_issue_ids]
  end

  def store_review(issue_bodies)
    StoreReview.call(
      project_path: project_path,
      source: 'local',
      branch_name: 'feature',
      base_ref: 'origin/main',
      base_commit_sha: 'base-sha',
      issue_data: issue_bodies.map { |body| { source_id: nil, body: body } }
    )
  end

  def insert_work_cycle(review_id:, role:, action:)
    db[:work_cycles].insert(
      created_at: Time.now,
      completed_at: nil,
      review_id: review_id,
      role: role,
      action: action,
      provider: nil,
      model: nil,
      reasoning_level: nil
    )
  end

  def review_issue_ids(review_id)
    db[:review_issues].where(review_id: review_id).order(:id).select_map(:reported_issue_id)
  end

  def git!(*arguments)
    stdout, stderr, status = Open3.capture3('git', '-C', project_path, *arguments)
    raise stderr unless status.success?

    stdout
  end
end
