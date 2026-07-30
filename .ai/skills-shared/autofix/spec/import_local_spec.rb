# frozen_string_literal: true

require 'json'
require 'tmpdir'
require_relative 'spec_helper'

RSpec.describe ImportLocal do
  let(:issues) { Database.connection[:reported_issues] }
  let(:json_path) { File.join(Dir.tmpdir, "autofix-local-spec-#{Process.pid}-#{object_id}.json") }

  after do
    FileUtils.rm_f(json_path)
  end

  it 'stores and displays local issues in order' do
    write_json(['First issue.', 'Second issue.'])

    output = described_class.call(path: json_path, project_path: '/project')
    rows = issues.order(:id).all

    expect(output).to eq("Issue: #{rows.first.fetch(:id)}\n\n> First issue.")
    expect(rows.map { |row| row.fetch(:body) }).to eq(['First issue.', 'Second issue.'])
    expect(rows).to all(
      include(
        project_path: '/project',
        source: 'local',
        source_id: nil,
        decision: nil
      )
    )
    expect(rows.map { |row| row.fetch(:id) }).to all(be_a(Integer))
    expect(rows.map { |row| row.fetch(:created_at) }).to all(be_a(Time))
  end

  it 'creates new rows when the same issues are imported again' do
    write_json(['First issue.', 'Second issue.'])

    2.times { described_class.call(path: json_path, project_path: '/project') }

    expect(issues.order(:id).select_map(:body)).to eq(
      ['First issue.', 'Second issue.', 'First issue.', 'Second issue.']
    )
  end

  it 'reports no issues without selecting an older local issue' do
    StoreIssue.call(project_path: '/project', source: 'local', body: 'Older issue.')
    write_json([])

    output = described_class.call(path: json_path, project_path: '/project')

    expect(output).to eq('No issues found.')
    expect(issues.count).to eq(1)
  end

  it 'raises for malformed JSON' do
    File.write(json_path, '[')

    expect { described_class.call(path: json_path, project_path: '/project') }.
      to raise_error(JSON::ParserError)
  end

  it 'requires an array of non-empty strings' do
    [{ 'issues' => [] }, [''], ['  '], ['Valid issue.', 2]].each do |payload|
      write_json(payload)

      expect { described_class.call(path: json_path, project_path: '/project') }.
        to raise_error(ArgumentError, 'Local issues must be an array of non-empty strings')
    end
    expect(issues.count).to eq(0)
  end

  def write_json(payload)
    File.write(json_path, JSON.generate(payload))
  end
end
