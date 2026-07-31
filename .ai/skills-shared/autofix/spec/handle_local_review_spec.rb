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
      state: 'manager_issue_selection'
    )
    expect(review_issues.where(review_id: review.fetch(:id)).order(:id).select_map(:reported_issue_id)).
      to eq(issues.map { |issue| issue.fetch(:id) })
  end

  it 'creates new issues and the next numbered Review when imported again' do
    write_json(review_input(issues: ['First issue.', 'Second issue.']))

    2.times { described_class.call(json_path: json_path, project_path: '/project') }

    expect(reported_issues.order(:id).select_map(:body)).to eq(
      ['First issue.', 'Second issue.', 'First issue.', 'Second issue.']
    )
    expect(reviews.order(:id).select_map(:number)).to eq([1, 2])
    expect(review_issues.count).to eq(4)
  end

  it 'numbers Reviews independently for each project' do
    write_json(review_input(issues: ['Issue.']))

    2.times { described_class.call(json_path: json_path, project_path: '/project') }
    described_class.call(json_path: json_path, project_path: '/other-project')

    expect(reviews.where(project_path: '/project').order(:id).select_map(:number)).to eq([1, 2])
    expect(reviews.where(project_path: '/other-project').select_map(:number)).to eq([1])
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

  def write_json(value)
    File.write(json_path, JSON.generate(value))
  end
end
