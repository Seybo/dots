# frozen_string_literal: true

require 'json'
require 'open3'
require 'tmpdir'
require_relative 'spec_helper'

RSpec.describe AutofixCli do
  let(:db) { Database.connection }
  let(:reported_issues) { db[:reported_issues] }
  let(:reviews) { db[:reviews] }
  let(:json_path) { File.join(Dir.tmpdir, "autofix-cli-spec-#{Process.pid}-#{object_id}.json") }
  let(:project_path) { Dir.mktmpdir('autofix-cli-project-spec') }

  before do
    allow(Database).to receive(:readonly_connection).and_return(db)
    git!('init', '-q')
    git!('config', 'user.email', 'autofix@example.com')
    git!('config', 'user.name', 'Autofix')
    File.write(File.join(project_path, 'tracked.txt'), "initial\n")
    git!('add', 'tracked.txt')
    git!('commit', '-q', '-m', 'Initial commit')
    allow(ResolveProjectPath).to receive(:call).and_return(project_path)
  end

  after do
    FileUtils.rm_f(json_path)
    FileUtils.remove_entry(project_path)
  end

  it 'imports a normalized GitHub Review' do
    write_json(review_input(issues: [{ 'source_id' => '101', 'body' => 'Normalized issue.' }]))

    expect do
      described_class.call(cli_args: ['import-github-review', json_path])
    end.to output("Issue: 1\n\n> Normalized issue.\n").to_stdout

    expect(reviews.first).to include(source: 'github', project_path: project_path)
    expect(reported_issues.first).to include(source: 'github', source_id: '101', body: 'Normalized issue.')
  end

  it 'imports a local Review with resolved Git metadata' do
    write_json(review_input(issues: ['Local issue.']))

    expect do
      described_class.call(cli_args: ['import-local-review', json_path])
    end.to output("Issue: 1\n\n> Local issue.\n").to_stdout

    expect(reviews.first).to include(
      source: 'local',
      project_path: project_path,
      branch_name: 'feature',
      active_base_ref: 'origin/main',
      active_base_commit_sha: 'base-sha'
    )
  end

  it 'does not create a Review for an empty import' do
    [
      ['import-github-review', review_input(issues: [])],
      ['import-local-review', review_input(issues: [])],
    ].each do |command, input|
      write_json(input)

      expect do
        described_class.call(cli_args: [command, json_path])
      end.to output("No issues found.\n").to_stdout
    end

    expect(reviews.count).to eq(0)
    expect(reported_issues.count).to eq(0)
  end

  it 'reports when resume finds no incomplete Review' do
    expect do
      described_class.call(cli_args: %w[resume feature])
    end.to output("No incomplete Review.\n").to_stdout
  end

  it 'shows participant-facing Work Cycle JSON' do
    review_id = store_review(['Approved issue.'])
    issue_id = review_issue_ids(review_id).first
    reported_issues.where(id: issue_id).update(decision: 'approved')
    work_cycle_id = StartImplementationWorkCycle.call(review_id: review_id)
    expected_output = ShowWorkCycle.call(work_cycle_id: work_cycle_id)
    allow(MigrateDatabase).to receive(:call)

    expect do
      described_class.call(cli_args: ['show-work-cycle', work_cycle_id.to_s])
    end.to output("#{expected_output}\n").to_stdout
    expect(MigrateDatabase).not_to have_received(:call)
  end

  it 'waits for and commits a completed implementation Work Cycle' do
    review_id = store_review(['Approved issue.'])
    issue_id = review_issue_ids(review_id).first
    reported_issues.where(id: issue_id).update(decision: 'approved')
    work_cycle_id = StartImplementationWorkCycle.call(review_id: review_id)
    File.write(File.join(project_path, 'tracked.txt'), "implemented\n")
    result_path = "/tmp/autofix-work-cycle-#{work_cycle_id}.json"
    File.write(
      result_path,
      JSON.generate(
        work_cycle_id: work_cycle_id,
        role: 'worker',
        action: 'implementation',
        status: 'completed',
        provider: nil,
        model: nil,
        reasoning_level: nil
      )
    )

    expected_output = Regexp.new(
      "Worker implementation completed \\(Cycle #{work_cycle_id}\\)\\.\\n" \
      'AutoFixCycle \d+\n' \
      'AutoFixRole reviewer\n'
    )
    begin
      expect do
        described_class.call(cli_args: ['wait-work-cycle', work_cycle_id.to_s])
      end.to output(expected_output).to_stdout
    ensure
      FileUtils.rm_f(result_path)
    end

    expect(reviews.where(id: review_id).get(:state)).to eq('reviewer_review')
  end

  it 'stores a decision and displays the next issue from the same Review' do
    store_review(['Unrelated issue.'])
    review_id = store_review(['First issue.', 'Second issue.'])
    issue_ids = review_issue_ids(review_id)

    expect do
      described_class.call(cli_args: ['store-decision', issue_ids.first.to_s, 'approved'])
    end.to output("Decision: approved\n\nIssue: #{issue_ids.last}\n\n> Second issue.\n").to_stdout

    expect(reported_issues.where(id: issue_ids.first).get(:decision)).to eq('approved')
  end

  it 'completes an all-skipped Review without creating a Work Cycle' do
    review_id = store_review(['Only issue.'])
    issue_id = review_issue_ids(review_id).first

    expect do
      described_class.call(cli_args: ['store-decision', issue_id.to_s, 'skipped'])
    end.to output("Decision: skipped\n\nNo unresolved issues.\n").to_stdout

    expect(reviews.where(id: review_id).first).to include(state: 'completed')
    expect(reviews.where(id: review_id).get(:completed_at)).not_to be_nil
    expect(db[:work_cycles].count).to eq(0)
  end

  it 'keeps the final decision when a dirty tree prevents Work Cycle creation' do
    review_id = store_review(['Approved issue.'])
    issue_id = review_issue_ids(review_id).first
    File.write(File.join(project_path, 'tracked.txt'), "changed\n")

    expect do
      described_class.call(cli_args: ['store-decision', issue_id.to_s, 'approved'])
    end.to raise_error(RuntimeError, /Working tree is not clean/)

    expect(reported_issues.where(id: issue_id).get(:decision)).to eq('approved')
    expect(reviews.where(id: review_id).first).to include(
      state: 'manager_issues_assessment',
      starting_commit_sha: nil
    )
    expect(db[:work_cycles].count).to eq(0)
  end

  it 'settles review-reported issues one at a time and stops when all are skipped' do
    review_id = store_review(['Original issue.'])
    original_issue_id = review_issue_ids(review_id).first
    reported_issues.where(id: original_issue_id).update(decision: 'approved')
    implementation_work_cycle_id = StartImplementationWorkCycle.call(review_id: review_id)
    db[:work_cycles].where(id: implementation_work_cycle_id).update(
      completed_at: Time.now
    )
    reviewer_work_cycle_id = StartReviewerReviewWorkCycle.call(review_id: review_id)
    StoreWorkCycleCompletion.call(
      work_cycle_id: reviewer_work_cycle_id,
      work_cycle_result: {
        'work_cycle_id' => reviewer_work_cycle_id,
        'role' => 'reviewer',
        'action' => 'review',
        'status' => 'completed',
        'provider' => nil,
        'model' => nil,
        'reasoning_level' => nil,
        'reported_issues' => ['First issue.', 'Second issue.']
      }
    )
    reported_issue_ids = db[:work_cycle_reported_issues].where(work_cycle_id: reviewer_work_cycle_id).
                         order(:id).select_map(:reported_issue_id)
    original_head = git!('rev-parse', 'HEAD').strip

    expect do
      described_class.call(cli_args: ['store-decision', reported_issue_ids.first.to_s, 'skipped'])
    end.to output(
      "Decision: skipped\n\nIssue: #{reported_issue_ids.last}\n\n> Second issue.\n"
    ).to_stdout
    expect do
      described_class.call(cli_args: ['store-decision', reported_issue_ids.last.to_s, 'skipped'])
    end.to output("No unresolved issues.\n").to_stdout

    expect(reported_issues.where(id: reported_issue_ids).select_map(:decision)).to eq(%w[skipped skipped])
    expect(reviews.where(id: review_id).first).to include(
      state: 'manager_issues_assessment',
      completed_at: nil
    )
    expect(db[:work_cycles].count).to eq(2)
    expect(git!('rev-parse', 'HEAD').strip).to eq(original_head)
  end

  it 'starts implementation after classifying a Review with an approved issue' do
    review_id = store_review(['Approved issue.', 'Skipped issue.'])
    issue_ids = review_issue_ids(review_id)

    expect do
      described_class.call(cli_args: ['store-decision', issue_ids.first.to_s, 'approved'])
    end.to output("Decision: approved\n\nIssue: #{issue_ids.last}\n\n> Skipped issue.\n").to_stdout
    expect do
      described_class.call(cli_args: ['store-decision', issue_ids.last.to_s, 'skipped'])
    end.to output(/Decision: skipped\n\nAutoFixCycle \d+\nAutoFixRole worker\n/).to_stdout

    expect(reviews.where(id: review_id).first).to include(
      state: 'worker_implementation',
      completed_at: nil,
      starting_commit_sha: git!('rev-parse', 'HEAD').strip
    )
    expect(db[:work_cycles].count).to eq(1)
  end

  def review_input(issues:)
    {
      'branch_name' => 'feature',
      'base_ref' => 'origin/main',
      'base_commit_sha' => 'base-sha',
      'issues' => issues
    }
  end

  def write_json(value)
    File.write(json_path, JSON.generate(value))
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
