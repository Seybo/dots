# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'open3'
require 'tmpdir'
require_relative '../../spec/spec_helper'

RSpec.describe 'Repeated external Reviews' do
  let(:db) { Database.connection }
  let(:root_path) { Dir.mktmpdir('autofix-repeated-reviews-spec') }
  let(:project_path) { File.join(root_path, 'project') }
  let(:task_path) { File.join(root_path, 'tasks', '0036-task') }
  let(:json_path) { File.join(root_path, 'local-review.json') }

  before do
    setup_repository
    setup_task
  end

  after do
    FileUtils.remove_entry(root_path)
  end

  it 'keeps completed Review history intact and dispatches only the next Review issue' do
    first_review_id = store_first_review
    first_issue_id = review_issue_ids(first_review_id).first
    db[:reported_issues].where(id: first_issue_id).update(decision: 'approved')
    first_implementation_id = StartImplementationWorkCycle.call(review_id: first_review_id)
    commit_first_implementation(first_implementation_id)
    complete_implementation(first_implementation_id)
    first_reviewer_id = store_first_reviewer_issue(first_review_id)
    first_reported_issue_id = db[:work_cycle_reported_issues].
                              where(work_cycle_id: first_reviewer_id).
                              get(:reported_issue_id)
    db[:reported_issues].where(id: first_reported_issue_id).update(decision: 'skipped')
    db[:reviews].where(id: first_review_id).update(state: 'completed', completed_at: Time.now)
    first_history = history(first_review_id)
    first_head_sha = git!('rev-parse', 'HEAD').strip

    write_local_review(['Original issue.'])
    HandleLocalReview.call(
      json_path: json_path,
      project_path: File.realpath(project_path),
      task_path: task_path
    )
    second_review = db[:reviews].order(:id).last
    second_issue_id = review_issue_ids(second_review.fetch(:id)).first
    db[:reported_issues].where(id: second_issue_id).update(decision: 'approved')

    second_implementation_id = StartImplementationWorkCycle.call(review_id: second_review.fetch(:id))

    expect(second_review).to include(number: 2, source: 'local')
    expect(second_issue_id).not_to eq(first_issue_id)
    expect(db[:work_cycles].where(id: second_implementation_id).first).to include(
      review_id: second_review.fetch(:id),
      role: 'worker',
      action: 'implementation'
    )
    expect(db[:work_cycle_inputs].where(work_cycle_id: second_implementation_id).
      select_map(:reported_issue_id)).to eq([second_issue_id])
    expect(review_issue_ids(second_review.fetch(:id))).to eq([second_issue_id])
    expect(review_issue_ids(second_review.fetch(:id))).not_to include(first_reported_issue_id)
    expect(history(first_review_id)).to eq(first_history)
    expect(git!('rev-parse', 'HEAD').strip).to eq(first_head_sha)
    expect(git!('log', '--format=%s').lines(chomp: true)).to include(
      "Work cycle #{first_implementation_id}"
    )
  end

  private

  def setup_repository
    FileUtils.mkdir_p(project_path)
    git!('init', '-q', '--initial-branch=main')
    git!('config', 'user.email', 'autofix@example.com')
    git!('config', 'user.name', 'Autofix')
    File.write(File.join(project_path, 'tracked.txt'), "base\n")
    git!('add', 'tracked.txt')
    git!('commit', '-q', '-m', 'Base')
    git!('checkout', '-q', '-b', 'feature')
  end

  def store_first_review
    StoreReview.call(
      task_context: task_context,
      source: 'local',
      starting_commit_sha: git!('rev-parse', 'HEAD').strip,
      issue_data: [{ source_id: nil, body: 'Original issue.' }]
    )
  end

  def setup_task
    FileUtils.mkdir_p(task_path)
    File.write(File.join(task_path, 'task.md'), "# Context\n")
    File.write(File.join(task_path, 'steps.md'), "# Steps\n\n## Step 1: Start\n")
    File.write(
      File.join(task_path, 'config.json'),
      JSON.generate(
        'branch' => {
          'name' => 'feature',
          'original_base_ref' => 'main',
          'original_base_commit_sha' => git!('rev-parse', 'main').strip,
          'active_base_ref' => 'main',
          'active_base_commit_sha' => git!('rev-parse', 'main').strip
        }
      )
    )
    db[:tasks].insert(
      created_at: Time.now,
      task_path: File.realpath(task_path),
      project_path: File.realpath(project_path),
      starting_commit_sha: git!('rev-parse', 'HEAD').strip,
      state: 'final_checks_passed',
      super_review_agent: 'claude'
    )
  end

  def task_context
    LoadCompletedTask.call(task_path: task_path, project_path: project_path)
  end

  def commit_first_implementation(work_cycle_id)
    File.write(File.join(project_path, 'tracked.txt'), "implemented\n")
    git!('add', 'tracked.txt')
    git!('commit', '-q', '-m', "Work cycle #{work_cycle_id}")
  end

  def complete_implementation(work_cycle_id)
    StoreWorkCycleCompletion.call(
      work_cycle_id: work_cycle_id,
      work_cycle_result: {
        'work_cycle_id' => work_cycle_id,
        'role' => 'worker',
        'action' => 'implementation',
        'status' => 'completed',
        'provider' => nil,
        'model' => nil,
        'reasoning_level' => nil
      }
    )
  end

  def store_first_reviewer_issue(review_id)
    work_cycle_id = db[:work_cycles].insert(
      created_at: Time.now,
      completed_at: nil,
      review_id: review_id,
      role: 'reviewer',
      action: 'review',
      provider: nil,
      model: nil,
      reasoning_level: nil
    )
    StoreWorkCycleCompletion.call(
      work_cycle_id: work_cycle_id,
      work_cycle_result: {
        'work_cycle_id' => work_cycle_id,
        'role' => 'reviewer',
        'action' => 'review',
        'status' => 'completed',
        'provider' => 'openai-codex',
        'model' => 'gpt-5.6-sol',
        'reasoning_level' => 'high',
        'reported_issues' => ['Historical reviewer issue.']
      }
    )
    work_cycle_id
  end

  def write_local_review(issue_bodies)
    File.write(
      json_path,
      JSON.generate(
        branch_name: 'feature',
        base_ref: 'main',
        base_commit_sha: git!('rev-parse', 'main').strip,
        issues: issue_bodies
      )
    )
  end

  def history(review_id)
    work_cycle_ids = db[:work_cycles].where(review_id: review_id).order(:id).select_map(:id)
    issue_ids = review_issue_ids(review_id)
    {
      review: db[:reviews].where(id: review_id).first,
      issues: db[:reported_issues].where(id: issue_ids).order(:id).all,
      review_issues: db[:review_issues].where(review_id: review_id).order(:id).all,
      work_cycles: db[:work_cycles].where(id: work_cycle_ids).order(:id).all,
      inputs: db[:work_cycle_inputs].where(work_cycle_id: work_cycle_ids).order(:id).all,
      reported_issues: db[:work_cycle_reported_issues].where(work_cycle_id: work_cycle_ids).order(:id).all
    }
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
