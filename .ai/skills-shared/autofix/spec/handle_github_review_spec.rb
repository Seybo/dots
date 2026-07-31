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
      state: 'manager_issue_selection'
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

  it 'does not create another Review for issues already assigned to one' do
    write_json(review_input(issues: [github_issue_data(101, 'First issue.')]))
    described_class.call(json_path: json_path, project_path: '/project')

    output = described_class.call(json_path: json_path, project_path: '/project')

    expect(output).to eq('No issues found.')
    expect(reported_issues.count).to eq(1)
    expect(reviews.count).to eq(1)
    expect(review_issues.count).to eq(1)
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
