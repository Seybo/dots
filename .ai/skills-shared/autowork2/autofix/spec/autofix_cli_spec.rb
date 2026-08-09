# frozen_string_literal: true

require 'json'
require 'open3'
require 'tmpdir'
require_relative '../../spec/spec_helper'

RSpec.describe AutofixCli do
  let(:db) { Database.connection }
  let(:json_path) { File.join(Dir.tmpdir, "autofix-cli-spec-#{Process.pid}-#{object_id}.json") }
  let(:project_path) { Dir.mktmpdir('autofix-cli-project-spec') }
  let(:task_path) { Dir.mktmpdir('autofix-cli-task-spec') }
  let(:task_id) { insert_task }

  before do
    allow(Database).to receive(:readonly_connection).and_return(db)
    git!('init', '-q')
    git!('config', 'user.email', 'autofix@example.com')
    git!('config', 'user.name', 'Autofix')
    File.write(File.join(project_path, 'tracked.txt'), "initial\n")
    git!('add', 'tracked.txt')
    git!('commit', '-q', '-m', 'Initial commit')
    git!('checkout', '-q', '-b', 'feature')
    write_task_files
    task_id
    allow(ResolveProjectPath).to receive(:call).and_return(project_path)
  end

  after do
    FileUtils.rm_f(json_path)
    FileUtils.remove_entry(project_path)
    FileUtils.remove_entry(task_path)
  end

  it 'imports a normalized GitHub Review' do
    write_json(review_input(issues: [{ 'source_id' => '101', 'body' => 'Normalized issue.' }]))

    expect do
      described_class.call(cli_args: ['import-github-review', json_path, task_path])
    end.to output("Issue: 1\n\n> Normalized issue.\n").to_stdout

    expect(reviews.first).to include(source: 'github', task_id: task_id, starting_commit_sha: head_sha)
    expect(reported_issues.first).to include(source: 'github', source_id: '101', body: 'Normalized issue.')
  end

  it 'imports a local Task-owned Review with its starting boundary' do
    write_json(review_input(issues: ['Local issue.']))

    expect do
      described_class.call(cli_args: ['import-local-review', json_path, task_path])
    end.to output("Issue: 1\n\n> Local issue.\n").to_stdout

    expect(reviews.first).to include(
      source: 'local',
      task_id: task_id,
      starting_commit_sha: head_sha
    )
  end

  it 'does not create a Review for an empty import' do
    [
      ['import-github-review', review_input(issues: [])],
      ['import-local-review', review_input(issues: [])],
    ].each do |command, input|
      write_json(input)

      expect do
        described_class.call(cli_args: [command, json_path, task_path])
      end.to output("No issues found.\n").to_stdout
    end

    expect(reviews.count).to eq(0)
    expect(reported_issues.count).to eq(0)
  end

  it 'reports when resume finds no incomplete Review' do
    expect do
      described_class.call(cli_args: ['resume', task_path])
    end.to output("No incomplete Review.\n").to_stdout
  end

  it 'starts a Task-owned rebase with an optional exact base ref' do
    allow(RebaseAutofixTask).to receive(:call).and_return('Task 1 rebased.')
    allow(ResumeReview).to receive(:call)

    expect do
      described_class.call(cli_args: ['rebase-task', task_path, 'origin/release'])
    end.to output("Task 1 rebased.\n").to_stdout
    expect(RebaseAutofixTask).to have_received(:call).with(
      project_path: project_path,
      task_path: task_path,
      base_ref: 'origin/release'
    )
    expect(ResumeReview).not_to have_received(:call)
  end

  it 'continues a Task-owned rebase with retained target metadata' do
    allow(ContinueAutofixRebase).to receive(:call).and_return('Task 1 rebased.')

    expect do
      described_class.call(
        cli_args: ['continue-task-rebase', task_path, 'origin/main', 'target-sha']
      )
    end.to output("Task 1 rebased.\n").to_stdout
    expect(ContinueAutofixRebase).to have_received(:call).with(
      project_path: project_path,
      task_path: task_path,
      target_base_ref: 'origin/main',
      target_base_commit_sha: 'target-sha'
    )
  end

  it 'squashes a completed Review without changing workflow state' do
    allow(SquashReview).to receive(:call).and_return('Review 1 squashed locally.')

    expect do
      described_class.call(cli_args: %w[squash-review 1])
    end.to output("Review 1 squashed locally.\n").to_stdout
    expect(SquashReview).to have_received(:call).with(review_id: '1', project_path: project_path)
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
    unrelated_review_id = store_review(['Unrelated issue.'])
    unrelated_issue_id = review_issue_ids(unrelated_review_id).first
    reported_issues.where(id: unrelated_issue_id).update(decision: 'skipped')
    reviews.where(id: unrelated_review_id).update(state: 'completed', completed_at: Time.now)
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
      starting_commit_sha: head_sha
    )
    expect(db[:work_cycles].count).to eq(0)
  end

  it 'settles skipped Reviewer issues and starts the final Worker review' do
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
    end.to output(/Decision: skipped\n\nAutoFixCycle \d+\nAutoFixRole worker\n/).to_stdout

    expect(reported_issues.where(id: reported_issue_ids).select_map(:decision)).to eq(%w[skipped skipped])
    expect(reviews.where(id: review_id).first).to include(
      state: 'worker_review',
      completed_at: nil
    )
    expect(db[:work_cycles].count).to eq(3)
    expect(db[:work_cycles].where(role: 'worker', action: 'review').count).to eq(1)
    expect(git!('rev-parse', 'HEAD').strip).to eq(original_head)
  end

  it 'moves all-skipped Worker issues directly to Manager review' do
    review_id = store_review(['Original issue.'])
    original_issue_id = review_issue_ids(review_id).first
    reported_issues.where(id: original_issue_id).update(decision: 'approved')
    implementation_work_cycle_id = StartImplementationWorkCycle.call(review_id: review_id)
    db[:work_cycles].where(id: implementation_work_cycle_id).update(completed_at: Time.now)
    reviews.where(id: review_id).update(state: 'reviewer_review')
    reviewer_work_cycle_id = StartReviewerReviewWorkCycle.call(review_id: review_id)
    StoreWorkCycleCompletion.call(
      work_cycle_id: reviewer_work_cycle_id,
      work_cycle_result: review_result(reviewer_work_cycle_id, role: 'reviewer', reported_issues: [])
    )
    worker_work_cycle_id = StartWorkerReviewWorkCycle.call(review_id: review_id)
    StoreWorkCycleCompletion.call(
      work_cycle_id: worker_work_cycle_id,
      work_cycle_result: review_result(
        worker_work_cycle_id,
        role: 'worker',
        reported_issues: ['Worker-reported issue.']
      )
    )
    reported_issue_id = reported_issues.where(source: 'worker').get(:id)

    expect do
      described_class.call(cli_args: ['store-decision', reported_issue_id.to_s, 'skipped'])
    end.to output("Decision: skipped\n\nNo unresolved issues.\n").to_stdout

    expect(reviews.where(id: review_id).first).to include(
      state: 'manager_review',
      completed_at: nil
    )
    expect(db[:work_cycles].where(role: 'worker', action: 'review').count).to eq(1)
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

  def reported_issues
    db[:reported_issues]
  end

  def reviews
    db[:reviews]
  end

  def review_input(issues:)
    {
      'branch_name' => 'feature',
      'base_ref' => 'main',
      'base_commit_sha' => head_sha,
      'issues' => issues
    }
  end

  def write_json(value)
    File.write(json_path, JSON.generate(value))
  end

  def insert_task
    db[:tasks].insert(
      created_at: Time.now,
      task_path: File.realpath(task_path),
      project_path: File.realpath(project_path),
      starting_commit_sha: head_sha,
      state: 'final_checks_passed',
      super_review_agent: 'claude'
    )
  end

  def write_task_files
    File.write(File.join(task_path, 'task.md'), "# Context\n")
    File.write(File.join(task_path, 'steps.md'), "# Steps\n\n## Step 1: Start\n")
    File.write(
      File.join(task_path, 'config.json'),
      JSON.generate(
        'branch' => {
          'name' => 'feature',
          'original_base_ref' => 'main',
          'original_base_commit_sha' => head_sha,
          'active_base_ref' => 'main',
          'active_base_commit_sha' => head_sha
        }
      )
    )
  end

  def task_context
    { task: db[:tasks].where(id: task_id).first, config: ReadTaskConfig.call(task_path: task_path) }
  end

  def head_sha
    git!('rev-parse', 'HEAD').strip
  end

  def store_review(issue_bodies)
    StoreReview.call(
      task_context: task_context,
      source: 'local',
      starting_commit_sha: head_sha,
      issue_data: issue_bodies.map { |body| { source_id: nil, body: body } }
    )
  end

  def review_issue_ids(review_id)
    db[:review_issues].where(review_id: review_id).order(:id).select_map(:reported_issue_id)
  end

  def review_result(work_cycle_id, role:, reported_issues:)
    {
      'work_cycle_id' => work_cycle_id,
      'role' => role,
      'action' => 'review',
      'status' => 'completed',
      'provider' => nil,
      'model' => nil,
      'reasoning_level' => nil,
      'reported_issues' => reported_issues
    }
  end

  def git!(*arguments)
    stdout, stderr, status = Open3.capture3('git', '-C', project_path, *arguments)
    raise stderr unless status.success?

    stdout
  end
end
