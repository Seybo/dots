# frozen_string_literal: true

require 'fileutils'
require 'open3'
require 'tmpdir'
require_relative '../../spec/spec_helper'

RSpec.describe StartManagerReviewWorkCycle do
  let(:db) { Database.connection }
  let(:project_path) { Dir.mktmpdir('autofix-manager-review-spec') }

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

  it 'creates a Manager review Work Cycle with every Review issue as input' do
    review_id = store_review
    issue_ids = db[:review_issues].where(review_id: review_id).order(:id).select_map(:reported_issue_id)
    db[:reported_issues].where(id: issue_ids.first).update(decision: 'approved', decision_reason: 'Approved in spec.')
    db[:reported_issues].where(id: issue_ids.last).update(decision: 'skipped', decision_reason: 'Skipped in spec.')
    manager_issue_id = StoreIssue.call(
      project_path: project_path,
      source: 'manager',
      body: 'Earlier Manager issue.'
    )
    db[:reported_issues].where(id: manager_issue_id).update(decision: 'skipped', decision_reason: 'Skipped in spec.')
    db[:review_issues].insert(
      created_at: Time.now,
      review_id: review_id,
      reported_issue_id: manager_issue_id
    )

    work_cycle_id = described_class.call(review_id: review_id)

    expect(db[:work_cycles].where(id: work_cycle_id).first).to include(
      review_id: review_id,
      role: 'manager',
      action: 'review',
      step_number: nil,
      completed_at: nil
    )
    expect(db[:work_cycle_inputs].where(work_cycle_id: work_cycle_id).order(:id).
      select_map(:reported_issue_id)).to eq(issue_ids + [manager_issue_id])
  end

  it 'fails before creating a Work Cycle when the tree is dirty' do
    review_id = store_review
    File.write(File.join(project_path, 'tracked.txt'), "dirty\n")

    expect { described_class.call(review_id: review_id) }.
      to raise_error(RuntimeError, /Working tree is not clean/)

    expect(db[:work_cycles].count).to eq(0)
  end

  def store_review
    review_id = ReviewFactory.call(
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
    db[:reviews].where(id: review_id).update(
      state: 'manager_review',
      starting_commit_sha: git!('rev-parse', 'HEAD').strip
    )
    review_id
  end

  def git!(*arguments)
    stdout, stderr, status = Open3.capture3('git', '-C', project_path, *arguments)
    raise stderr unless status.success?

    stdout
  end
end
