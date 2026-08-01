# frozen_string_literal: true

require 'json'
require 'tmpdir'
require_relative 'spec_helper'

RSpec.describe HandleLocalReview do
  let(:db) { Database.connection }
  let(:reported_issues) { db[:reported_issues] }
  let(:reviews) { db[:reviews] }
  let(:review_issues) { db[:review_issues] }
  let(:json_path) { File.join(Dir.tmpdir, "autofix-local-spec-#{Process.pid}-#{object_id}.json") }

  after do
    FileUtils.rm_f(json_path)
  end

  it 'stores local issues and creates one Review atomically' do
    write_json(review_input(issues: ['First issue.', 'Second issue.']))

    output = described_class.call(json_path: json_path, project_path: '/project')
    issues = reported_issues.order(:id).all
    review = reviews.first

    expect(output).to eq("Issue: #{issues.first.fetch(:id)}\n\n> First issue.")
    expect(issues.map { |issue| issue.fetch(:body) }).to eq(['First issue.', 'Second issue.'])
    expect(issues).to all(
      include(
        project_path: '/project',
        source: 'local',
        source_id: nil,
        decision: nil
      )
    )
    expect(review).to include(
      project_path: '/project',
      number: 1,
      source: 'local',
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

  it 'creates fresh issues and the next numbered Review after the first Review completes' do
    write_json(review_input(issues: ['First issue.', 'Second issue.']))

    described_class.call(json_path: json_path, project_path: '/project')
    first_review = reviews.first
    first_issue_ids = review_issues.where(review_id: first_review.fetch(:id)).order(:id).
                      select_map(:reported_issue_id)
    first_issues = reported_issues.where(id: first_issue_ids).order(:id).all
    complete_review(first_review)
    described_class.call(json_path: json_path, project_path: '/project')

    second_review = reviews.order(:id).last
    second_issue_ids = review_issues.where(review_id: second_review.fetch(:id)).order(:id).
                       select_map(:reported_issue_id)
    expect(reported_issues.order(:id).select_map(:body)).to eq(
      ['First issue.', 'Second issue.', 'First issue.', 'Second issue.']
    )
    expect(second_issue_ids).not_to include(*first_issue_ids)
    expect(reported_issues.where(id: first_issue_ids).order(:id).all).to eq(first_issues)
    expect(reviews.order(:id).select_map(:number)).to eq([1, 2])
    expect(review_issues.count).to eq(4)
  end

  it 'numbers Reviews independently for each project' do
    write_json(review_input(issues: ['Issue.']))

    described_class.call(json_path: json_path, project_path: '/project')
    complete_review(reviews.first)
    described_class.call(json_path: json_path, project_path: '/project')
    described_class.call(json_path: json_path, project_path: '/other-project')

    expect(reviews.where(project_path: '/project').order(:id).select_map(:number)).to eq([1, 2])
    expect(reviews.where(project_path: '/other-project').select_map(:number)).to eq([1])
  end

  it 'continues project numbering when the external source changes' do
    first_review_id = StoreReview.call(
      project_path: '/project',
      source: 'github',
      branch_name: 'feature',
      base_ref: 'origin/main',
      base_commit_sha: 'base-sha',
      issue_data: [{ source_id: '101', body: 'GitHub issue.' }]
    )
    complete_review(reviews.where(id: first_review_id).first)
    write_json(review_input(issues: ['Local issue.']))

    described_class.call(json_path: json_path, project_path: '/project')

    expect(reviews.order(:id).select_map(%i[number source])).to eq([[1, 'github'], [2, 'local']])
  end

  it 'rolls back new local issues when the project already has an active Review' do
    write_json(review_input(issues: ['First issue.']))
    described_class.call(json_path: json_path, project_path: '/project')
    original_review = reviews.first
    original_issue = reported_issues.first
    write_json(review_input(issues: ['New issue.']))

    expect { described_class.call(json_path: json_path, project_path: '/project') }.
      to raise_error(Sequel::UniqueConstraintViolation)

    expect(reviews.all).to eq([original_review])
    expect(reported_issues.all).to eq([original_issue])
    expect(review_issues.all).to contain_exactly(
      include(review_id: original_review.fetch(:id), reported_issue_id: original_issue.fetch(:id))
    )
  end

  it 'reports no issues without creating a Review or selecting older issues' do
    StoreIssue.call(project_path: '/project', source: 'local', body: 'Older issue.')
    write_json(review_input(issues: []))

    output = described_class.call(json_path: json_path, project_path: '/project')

    expect(output).to eq('No issues found.')
    expect(reported_issues.count).to eq(1)
    expect(reviews.count).to eq(0)
    expect(review_issues.count).to eq(0)
  end

  it 'raises for malformed JSON without storing import state' do
    File.write(json_path, '[')

    expect { described_class.call(json_path: json_path, project_path: '/project') }.
      to raise_error(JSON::ParserError)
    expect(reported_issues.count).to eq(0)
    expect(reviews.count).to eq(0)
    expect(review_issues.count).to eq(0)
  end

  it 'requires import metadata' do
    write_json('issues' => ['Issue.'])

    expect { described_class.call(json_path: json_path, project_path: '/project') }.to raise_error(KeyError)
    expect(reported_issues.count).to eq(0)
    expect(reviews.count).to eq(0)
  end

  it 'requires an array of non-empty issue strings' do
    [[''], ['  '], ['Valid issue.', 2]].each do |invalid_issues|
      write_json(review_input(issues: invalid_issues))

      expect { described_class.call(json_path: json_path, project_path: '/project') }.
        to raise_error(ArgumentError, 'Local issues must be an array of non-empty strings')
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

  def complete_review(review)
    reviews.where(id: review.fetch(:id)).update(state: 'completed', completed_at: Time.now)
  end

  def write_json(value)
    File.write(json_path, JSON.generate(value))
  end
end
