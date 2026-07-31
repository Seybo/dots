# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'open3'
require 'tmpdir'
require_relative 'spec_helper'

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
      'previous_implementation_commit_sha' => nil,
      'previous_work_cycle_id' => nil,
      'inputs' => [
        {
          'id' => issue_id,
          'source' => 'local',
          'body' => 'Approved issue.'
        },
      ],
      'findings' => []
    )
  end

  it 'returns the nearest preceding implementation commit and review findings' do
    review_id = StoreReview.call(
      project_path: project_path,
      source: 'local',
      branch_name: 'feature',
      base_ref: 'origin/main',
      base_commit_sha: 'base-sha',
      issue_data: [{ source_id: nil, body: 'Original issue.' }]
    )
    implementation_id = insert_work_cycle(
      review_id: review_id,
      role: 'worker',
      action: 'implementation',
      commit_sha: 'implementation-sha'
    )
    review_work_cycle_id = insert_work_cycle(
      review_id: review_id,
      previous_work_cycle_id: implementation_id,
      role: 'reviewer',
      action: 'review'
    )
    finding_id = StoreIssue.call(
      project_path: project_path,
      source: 'reviewer',
      body: 'Review finding.'
    )
    db[:work_cycle_findings].insert(
      created_at: Time.now,
      work_cycle_id: review_work_cycle_id,
      reported_issue_id: finding_id
    )

    context = JSON.parse(described_class.call(work_cycle_id: review_work_cycle_id))

    expect(context.fetch('previous_implementation_commit_sha')).to eq('implementation-sha')
    expect(context.fetch('findings')).to eq(
      [{ 'id' => finding_id, 'source' => 'reviewer', 'body' => 'Review finding.' }]
    )
  end

  def insert_work_cycle(review_id:, role:, action:, previous_work_cycle_id: nil, commit_sha: nil)
    db[:work_cycles].insert(
      created_at: Time.now,
      completed_at: commit_sha.nil? ? nil : Time.now,
      review_id: review_id,
      previous_work_cycle_id: previous_work_cycle_id,
      role: role,
      action: action,
      result: nil,
      provider: nil,
      model: nil,
      reasoning_level: nil,
      commit_sha: commit_sha
    )
  end

  def git!(*arguments)
    stdout, stderr, status = Open3.capture3('git', '-C', project_path, *arguments)
    raise stderr unless status.success?

    stdout
  end
end
