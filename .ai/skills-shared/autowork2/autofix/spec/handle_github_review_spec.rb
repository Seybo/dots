# frozen_string_literal: true

require 'json'
require 'open3'
require 'tmpdir'
require_relative '../../spec/spec_helper'

RSpec.describe HandleGithubReview do
  let(:db) { Database.connection }
  let(:root_path) { Dir.mktmpdir('autofix-github-review-spec') }
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

  it 'stores normalized GitHub issues and creates one Task-owned Review atomically' do
    write_json(
      review_input(issues: [github_issue_data(101, 'First issue.'), github_issue_data(102, 'Second issue.')])
    )

    output = handle
    issues = reported_issues.order(:id).all
    review = reviews.first

    expect(output).to eq("Issue: #{issues.first.fetch(:id)}\n\n> First issue.")
    expect(issues.map { |issue| issue.values_at(:source_id, :body) }).to eq(
      [['101', 'First issue.'], ['102', 'Second issue.']]
    )
    expect(review).to include(
      task_id: task_id,
      number: 1,
      source: 'github',
      starting_commit_sha: head_sha,
      state: 'manager_issues_assessment'
    )
    expect(review_issues.where(review_id: review.fetch(:id)).order(:id).select_map(:reported_issue_id)).
      to eq(issues.map { |issue| issue.fetch(:id) })
  end

  it 'refreshes an unresolved unassigned issue before adding it to a Review' do
    issue_id = StoreIssue.call(
      project_path: File.realpath(project_path),
      source: 'github',
      source_id: '101',
      body: 'Old body.'
    )
    write_json(review_input(issues: [github_issue_data(101, 'Normalized body.')]))

    handle

    expect(reported_issues.where(id: issue_id).get(:body)).to eq('Normalized body.')
    expect(review_issues.get(:reported_issue_id)).to eq(issue_id)
  end

  it 'creates only new comment IDs in the next Task-scoped Review' do
    write_json(review_input(issues: [github_issue_data(101, 'First issue.')]))
    handle
    first_review = reviews.first
    first_issue = reported_issues.first
    reported_issues.where(id: first_issue.fetch(:id)).update(decision: 'skipped')
    complete_review(first_review)
    write_json(
      review_input(
        issues: [github_issue_data(101, 'Edited issue.'), github_issue_data(102, 'New issue.')]
      )
    )

    output = handle

    second_review = reviews.order(:id).last
    second_issue = reported_issues.order(:id).last
    expect(output).to eq("Issue: #{second_issue.fetch(:id)}\n\n> New issue.")
    expect(reviews.order(:id).select_map(%i[task_id number])).to eq([[task_id, 1], [task_id, 2]])
    expect(reported_issues.where(id: first_issue.fetch(:id)).first).
      to eq(first_issue.merge(decision: 'skipped'))
    expect(review_issues.where(review_id: second_review.fetch(:id)).select_map(:reported_issue_id)).
      to eq([second_issue.fetch(:id)])
  end

  it 'rolls back a new issue when the Task already has an active Review' do
    write_json(review_input(issues: [github_issue_data(101, 'First issue.')]))
    handle
    original_review = reviews.first
    original_issue = reported_issues.first
    write_json(review_input(issues: [github_issue_data(102, 'New issue.')]))

    expect { handle }.to raise_error(Sequel::UniqueConstraintViolation)

    expect(reviews.all).to eq([original_review])
    expect(reported_issues.all).to eq([original_issue])
  end

  it 'requires exact configured branch and active base before persistence' do
    write_json(review_input(branch_name: 'other', issues: [github_issue_data(101, 'Issue.')]))
    expect { handle }.to raise_error('GitHub Review branch other does not match Task branch feature')

    write_json(
      review_input(
        base_ref: 'origin/main',
        base_commit_sha: 'advanced-sha',
        issues: [github_issue_data(101, 'Issue.')]
      )
    )
    expect { handle }.
      to raise_error(%r{Run --rebase-base origin/main before importing the Review})
    expect(reviews.count).to eq(0)
    expect(reported_issues.count).to eq(0)
  end

  it 'reports no issues without creating a Review' do
    write_json(review_input(issues: []))

    expect(handle).to eq('No issues found.')
    expect(reported_issues.count).to eq(0)
    expect(reviews.count).to eq(0)
  end

  it 'rolls back issue changes and the Review when a relationship constraint fails' do
    duplicate = github_issue_data(101, 'First issue.')
    write_json(review_input(issues: [duplicate, duplicate]))

    expect { handle }.to raise_error(Sequel::UniqueConstraintViolation)
    expect(reported_issues.count).to eq(0)
    expect(reviews.count).to eq(0)
  end

  it 'requires source ID and body fields' do
    [
      review_input(issues: [{ 'source_id' => 101 }]),
      review_input(issues: [{ 'body' => 'Issue.' }]),
    ].each do |value|
      write_json(value)

      expect { handle }.to raise_error(KeyError)
    end
    expect(reported_issues.count).to eq(0)
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
    git!('checkout', '-q', '-b', 'feature')
  end

  def write_task_files
    FileUtils.mkdir_p(task_path)
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

  def review_input(issues:, branch_name: 'feature', base_ref: 'main', base_commit_sha: head_sha)
    {
      'branch_name' => branch_name,
      'base_ref' => base_ref,
      'base_commit_sha' => base_commit_sha,
      'issues' => issues
    }
  end

  def github_issue_data(source_id, body)
    { 'source_id' => source_id, 'body' => body }
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
