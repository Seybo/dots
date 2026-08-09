# frozen_string_literal: true

require 'json'
require 'open3'
require 'tmpdir'
require_relative '../../spec/spec_helper'

RSpec.describe HandleLocalReview do
  let(:db) { Database.connection }
  let(:root_path) { Dir.mktmpdir('autofix-local-review-spec') }
  let(:project_path) { File.join(root_path, 'project') }
  let(:task_path) { File.join(root_path, 'tasks', '0036-task') }
  let(:json_path) { File.join(root_path, 'review.json') }

  before do
    initialize_repository
    write_task_files
    task_id
  end

  after do
    FileUtils.remove_entry(root_path)
  end

  it 'stores local issues and creates one Task-owned Review atomically' do
    write_json('issues' => ['First issue.', 'Second issue.'])

    output = handle
    issues = reported_issues.order(:id).all
    review = reviews.first

    expect(output).to eq("Issue: #{issues.first.fetch(:id)}\n\n> First issue.")
    expect(issues.map { |issue| issue.fetch(:body) }).to eq(['First issue.', 'Second issue.'])
    expect(issues).to all(
      include(
        project_path: File.realpath(project_path),
        source: 'local',
        source_id: nil,
        decision: nil
      )
    )
    expect(review).to include(
      task_id: task_id,
      number: 1,
      source: 'local',
      starting_commit_sha: head_sha,
      state: 'manager_issues_assessment'
    )
    expect(review_issues.where(review_id: review.fetch(:id)).order(:id).select_map(:reported_issue_id)).
      to eq(issues.map { |issue| issue.fetch(:id) })
  end

  it 'creates fresh issues and the next numbered Review for the same Task' do
    write_json('issues' => ['First issue.'])
    handle
    first_review = reviews.first
    first_issue = reported_issues.first
    complete_review(first_review)

    handle

    expect(reviews.order(:id).select_map(%i[task_id number])).to eq([[task_id, 1], [task_id, 2]])
    expect(reported_issues.order(:id).select_map(:body)).to eq(['First issue.', 'First issue.'])
    expect(reported_issues.order(:id).last.fetch(:id)).not_to eq(first_issue.fetch(:id))
  end

  it 'continues Task numbering when the external source changes' do
    first_review_id = StoreReview.call(
      task_context: task_context,
      source: 'github',
      starting_commit_sha: head_sha,
      issue_data: [{ source_id: '101', body: 'GitHub issue.' }]
    )
    complete_review(reviews.where(id: first_review_id).first)
    write_json('issues' => ['Local issue.'])

    handle

    expect(reviews.order(:id).select_map(%i[number source])).to eq([[1, 'github'], [2, 'local']])
  end

  it 'rolls back new local issues when the Task already has an active Review' do
    write_json('issues' => ['First issue.'])
    handle
    original_review = reviews.first
    original_issue = reported_issues.first
    write_json('issues' => ['New issue.'])

    expect { handle }.to raise_error(Sequel::UniqueConstraintViolation)

    expect(reviews.all).to eq([original_review])
    expect(reported_issues.all).to eq([original_issue])
  end

  it 'reports no issues without creating a Review or selecting older issues' do
    StoreIssue.call(project_path: project_path, source: 'local', body: 'Older issue.')
    write_json('issues' => [])

    expect(handle).to eq('No issues found.')
    expect(reported_issues.count).to eq(1)
    expect(reviews.count).to eq(0)
  end

  it 'raises for malformed or invalid issue input without storing state' do
    File.write(json_path, '[')
    expect { handle }.to raise_error(JSON::ParserError)

    [[''], ['  '], ['Valid issue.', 2]].each do |invalid_issues|
      write_json('issues' => invalid_issues)
      expect { handle }.
        to raise_error(ArgumentError, 'Local issues must be an array of non-empty strings')
    end
    expect(reported_issues.count).to eq(0)
    expect(reviews.count).to eq(0)
  end

  it 'requires only the issues field from local transport' do
    write_json('other' => 'value')

    expect { handle }.to raise_error(KeyError)
    expect(reviews.count).to eq(0)
  end

  private

  def reported_issues
    db[:reported_issues]
  end

  def reviews
    db[:reviews]
  end

  def review_issues
    db[:review_issues]
  end

  def task_id
    @task_id ||= setup_task
  end

  def handle
    described_class.call(json_path: json_path, project_path: project_path, task_path: task_path)
  end

  def task_context
    LoadCompletedTask.call(task_path: task_path, project_path: project_path)
  end

  def setup_task
    db[:tasks].insert(
      created_at: Time.now,
      task_path: File.realpath(task_path),
      project_path: File.realpath(project_path),
      starting_commit_sha: head_sha,
      state: 'final_checks_passed',
      super_review_agent: 'claude'
    )
  end

  def initialize_repository
    FileUtils.mkdir_p(project_path)
    git!('init', '-q', '--initial-branch=main')
    git!('config', 'user.email', 'autofix@example.com')
    git!('config', 'user.name', 'Autofix')
    File.write(File.join(project_path, 'tracked.txt'), "initial\n")
    git!('add', 'tracked.txt')
    git!('commit', '-q', '-m', 'Initial')
  end

  def write_task_files
    FileUtils.mkdir_p(task_path)
    File.write(File.join(task_path, 'task.md'), "# Context\n")
    File.write(File.join(task_path, 'steps.md'), "# Steps\n\n## Step 1: Start\n")
    File.write(
      File.join(task_path, 'config.json'),
      JSON.generate(
        'branch' => {
          'name' => 'main',
          'original_base_ref' => head_sha,
          'original_base_commit_sha' => head_sha,
          'active_base_ref' => head_sha,
          'active_base_commit_sha' => head_sha
        }
      )
    )
  end

  def complete_review(review)
    reviews.where(id: review.fetch(:id)).update(state: 'completed', completed_at: Time.now)
  end

  def head_sha
    git!('rev-parse', 'HEAD').strip
  end

  def write_json(value)
    File.write(json_path, JSON.generate(value))
  end

  def git!(*arguments)
    stdout, stderr, status = Open3.capture3('git', '-C', project_path, *arguments)
    raise stderr unless status.success?

    stdout
  end
end
