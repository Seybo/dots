# frozen_string_literal: true

require 'json'
require 'tmpdir'
require_relative 'spec_helper'

RSpec.describe HandleGithubReview do
  let(:db) { Database.connection }
  let(:reported_issues) { db[:reported_issues] }
  let(:reviews) { db[:reviews] }
  let(:review_issues) { db[:review_issues] }
  let(:json_path) { File.join(Dir.tmpdir, "autofix-github-spec-#{Process.pid}-#{object_id}.json") }

  after do
    FileUtils.rm_f(json_path)
  end

  it 'stores normalized GitHub issues and creates one Review atomically' do
    write_json(
      review_input(issues: [github_issue_data(101, 'First issue.'), github_issue_data(102, 'Second issue.')])
    )

    output = described_class.call(json_path: json_path, project_path: '/project')
    issues = reported_issues.order(:id).all
    review = reviews.first

    expect(output).to eq("Issue: #{issues.first.fetch(:id)}\n\n> First issue.")
    expect(issues.map { |issue| issue.values_at(:source_id, :body) }).to eq(
      [['101', 'First issue.'], ['102', 'Second issue.']]
    )
    expect(review).to include(
      project_path: '/project',
      number: 1,
      source: 'github',
      branch_name: 'feature',
      original_base_ref: 'origin/main',
      original_base_commit_sha: 'base-sha',
      active_base_ref: 'origin/main',
      active_base_commit_sha: 'base-sha',
      state: 'manager_issues_assessment'
    )
    expect(review_issues.where(review_id: review.fetch(:id)).order(:id).select_map(:reported_issue_id)).
      to eq(issues.map { |issue| issue.fetch(:id) })
  end

  it 'refreshes an unresolved unassigned issue before adding it to a Review' do
    issue_id = StoreIssue.call(
      project_path: '/project',
      source: 'github',
      source_id: '101',
      body: 'Old body.'
    )
    write_json(review_input(issues: [github_issue_data(101, 'Normalized body.')]))

    described_class.call(json_path: json_path, project_path: '/project')

    expect(reported_issues.where(id: issue_id).get(:body)).to eq('Normalized body.')
    expect(review_issues.get(:reported_issue_id)).to eq(issue_id)
  end

  it 'does not create another Review for a processed comment ID after completion' do
    write_json(review_input(issues: [github_issue_data(101, 'First issue.')]))
    described_class.call(json_path: json_path, project_path: '/project')
    original_review = reviews.first
    original_issue = reported_issues.first
    reported_issues.where(id: original_issue.fetch(:id)).update(decision: 'skipped')
    complete_review(original_review)
    write_json(review_input(issues: [github_issue_data(101, 'Edited issue.')]))

    output = described_class.call(json_path: json_path, project_path: '/project')

    expect(output).to eq('No issues found.')
    expect(reported_issues.all).to eq([original_issue.merge(decision: 'skipped')])
    expect(reviews.count).to eq(1)
    expect(reviews.where(id: original_review.fetch(:id)).first).
      to include(state: 'completed', completed_at: be_a(Time))
    expect(review_issues.count).to eq(1)
  end

  it 'creates the next Review from only new comment IDs' do
    write_json(review_input(issues: [github_issue_data(101, 'First issue.')]))
    described_class.call(json_path: json_path, project_path: '/project')
    first_review = reviews.first
    first_issue = reported_issues.first
    reported_issues.where(id: first_issue.fetch(:id)).update(decision: 'skipped')
    complete_review(first_review)
    write_json(
      review_input(
        issues: [github_issue_data(101, 'Edited issue.'), github_issue_data(102, 'New issue.')]
      )
    )

    output = described_class.call(json_path: json_path, project_path: '/project')

    second_review = reviews.order(:id).last
    second_issue = reported_issues.order(:id).last
    expect(output).to eq("Issue: #{second_issue.fetch(:id)}\n\n> New issue.")
    expect(reviews.order(:id).select_map(:number)).to eq([1, 2])
    expect(reported_issues.where(id: first_issue.fetch(:id)).first).
      to eq(first_issue.merge(decision: 'skipped'))
    expect(second_issue).to include(source_id: '102', body: 'New issue.', decision: nil)
    expect(review_issues.where(review_id: second_review.fetch(:id)).select_map(:reported_issue_id)).
      to eq([second_issue.fetch(:id)])
  end

  it 'rolls back a new issue when the project already has an active Review' do
    write_json(review_input(issues: [github_issue_data(101, 'First issue.')]))
    described_class.call(json_path: json_path, project_path: '/project')
    original_review = reviews.first
    original_issue = reported_issues.first
    write_json(review_input(issues: [github_issue_data(102, 'New issue.')]))

    expect { described_class.call(json_path: json_path, project_path: '/project') }.
      to raise_error(Sequel::UniqueConstraintViolation)

    expect(reviews.all).to eq([original_review])
    expect(reported_issues.all).to eq([original_issue])
    expect(review_issues.all).to contain_exactly(
      include(review_id: original_review.fetch(:id), reported_issue_id: original_issue.fetch(:id))
    )
  end

  it 'reports no issues without creating a Review' do
    write_json(review_input(issues: []))

    output = described_class.call(json_path: json_path, project_path: '/project')

    expect(output).to eq('No issues found.')
    expect(reported_issues.count).to eq(0)
    expect(reviews.count).to eq(0)
  end

  it 'rolls back issue changes and the Review when a Review issue constraint fails' do
    duplicate = github_issue_data(101, 'First issue.')
    write_json(review_input(issues: [duplicate, duplicate]))

    expect { described_class.call(json_path: json_path, project_path: '/project') }.
      to raise_error(Sequel::UniqueConstraintViolation)
    expect(reported_issues.count).to eq(0)
    expect(reviews.count).to eq(0)
    expect(review_issues.count).to eq(0)
  end

  it 'requires source ID and body fields' do
    [
      review_input(issues: [{ 'source_id' => 101 }]),
      review_input(issues: [{ 'body' => 'Issue.' }]),
    ].each do |value|
      write_json(value)

      expect { described_class.call(json_path: json_path, project_path: '/project') }.
        to raise_error(KeyError)
    end
    expect(reported_issues.count).to eq(0)
    expect(reviews.count).to eq(0)
  end

  def complete_review(review)
    reviews.where(id: review.fetch(:id)).update(state: 'completed', completed_at: Time.now)
  end

  def review_input(issues:)
    {
      'branch_name' => 'feature',
      'base_ref' => 'origin/main',
      'base_commit_sha' => 'base-sha',
      'issues' => issues
    }
  end

  def github_issue_data(source_id, body)
    { 'source_id' => source_id, 'body' => body }
  end

  def write_json(value)
    File.write(json_path, JSON.generate(value))
  end
end
