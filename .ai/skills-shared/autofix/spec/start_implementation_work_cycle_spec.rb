# frozen_string_literal: true

require 'fileutils'
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
      previous_work_cycle_id: nil,
      role: 'worker',
      action: 'implementation',
      completed_at: nil,
      result: nil,
      commit_sha: nil
    )
    expect(db[:work_cycle_inputs].where(work_cycle_id: work_cycle_id).select_map(:reported_issue_id)).
      to eq([issue_ids.first])
    expect(db[:reviews].where(id: review_id).first).to include(
      state: 'worker_implementation',
      starting_commit_sha: git!('rev-parse', 'HEAD').strip
    )
  end

  it 'keeps approved review inputs eligible for implementation' do
    review_id = store_review(['Approved issue.'])
    issue_id = review_issue_ids(review_id).first
    db[:reported_issues].where(id: issue_id).update(decision: 'approved')
    review_work_cycle_id = db[:work_cycles].insert(
      created_at: Time.now,
      completed_at: Time.now,
      review_id: review_id,
      previous_work_cycle_id: nil,
      role: 'worker',
      action: 'review',
      result: 'Reviewed.',
      provider: nil,
      model: nil,
      reasoning_level: nil,
      commit_sha: nil
    )
    db[:work_cycle_inputs].insert(
      created_at: Time.now,
      work_cycle_id: review_work_cycle_id,
      reported_issue_id: issue_id
    )

    implementation_work_cycle_id = described_class.call(review_id: review_id)

    expect(db[:work_cycle_inputs].where(work_cycle_id: implementation_work_cycle_id).select_map(:reported_issue_id)).
      to eq([issue_id])
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
      state: 'manager_issue_selection',
      starting_commit_sha: nil
    )
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

  def review_issue_ids(review_id)
    db[:review_issues].where(review_id: review_id).order(:id).select_map(:reported_issue_id)
  end

  def git!(*arguments)
    stdout, stderr, status = Open3.capture3('git', '-C', project_path, *arguments)
    raise stderr unless status.success?

    stdout
  end
end
