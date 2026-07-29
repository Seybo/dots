# frozen_string_literal: true

require 'json'
require 'tmpdir'
require 'rspec'

load File.expand_path('../scripts/validate-adjudication', __dir__)

# rubocop:disable Metrics/BlockLength
RSpec.describe SuperReview::AdjudicationValidator do
  around do |example|
    Dir.mktmpdir('super-review-validator-spec') do |dir|
      @tmpdir = dir
      example.run
    end
  end

  def write_json(name, data)
    path = File.join(@tmpdir, name)
    File.write(path, JSON.pretty_generate(data))
    path
  end

  def candidate(id, source_group)
    {
      'id' => id,
      'source_group' => source_group,
      'claim' => "Claim #{id}",
      'severity' => 'HIGH',
      'trigger' => "Trigger #{id}"
    }
  end

  def decision(id, value)
    row = { 'id' => id, 'decision' => value, 'rationale' => "Rationale #{id}" }
    return row.merge(agree_evidence(id)) if value == 'AGREE'

    row['missing_evidence'] = "Missing evidence #{id}" if value == 'NEEDS_CONTEXT'
    row
  end

  def agree_evidence(id)
    {
      'trigger' => "Trigger #{id}",
      'mechanism' => "Mechanism #{id}",
      'reachability_source' => 'task_contract',
      'evidence' => "Evidence #{id}"
    }
  end

  def validate(candidates, adjudications)
    candidates_path = write_json('candidates.json', 'candidates' => candidates)
    adjudication_paths = adjudications.map.with_index do |adjudication, index|
      write_json("adjudication#{index}.json", adjudication)
    end
    described_class.new(
      candidates_path: candidates_path,
      adjudication_paths: adjudication_paths
    ).validate
  end

  it 'accepts an empty candidate manifest without adjudication' do
    result = validate([], [])

    expect(result).to include(
      'valid' => true,
      'candidate_count' => 0,
      'is_degenerate' => false,
      'requires_manual_verification' => false
    )
    expect(result['actionable_candidate_ids']).to be_empty
  end

  it 'marks six of six agreements as degenerate and non-actionable' do
    candidates = 6.times.map { |index| candidate("I#{index + 1}", 'independent') }
    adjudication = {
      'source_group' => 'independent',
      'decisions' => candidates.map { |row| decision(row.fetch('id'), 'AGREE') }
    }

    result = validate(candidates, [adjudication])

    expect(result['valid']).to be(true)
    expect(result.dig('groups', 'independent')).to include(
      'agree_count' => 6,
      'agreement_ratio' => 1.0,
      'is_degenerate' => true
    )
    expect(result['actionable_candidate_ids']).to be_empty
    expect(result['manual_verification_candidate_ids']).to match_array(candidates.map { |row| row.fetch('id') })
  end

  it 'marks twelve of fifteen agreements as degenerate' do
    candidates = 15.times.map { |index| candidate("P#{index + 1}", 'panel') }
    decisions = candidates.each_with_index.map do |row, index|
      decision(row.fetch('id'), index < 12 ? 'AGREE' : 'DISAGREE')
    end

    result = validate(candidates, [{ 'source_group' => 'panel', 'decisions' => decisions }])

    expect(result.dig('groups', 'panel')).to include(
      'agreement_ratio' => 0.8,
      'is_degenerate' => true
    )
  end

  it 'does not mark exactly seventy percent agreement as degenerate' do
    candidates = 10.times.map { |index| candidate("P#{index + 1}", 'panel') }
    decisions = candidates.each_with_index.map do |row, index|
      decision(row.fetch('id'), index < 7 ? 'AGREE' : 'DISAGREE')
    end

    result = validate(candidates, [{ 'source_group' => 'panel', 'decisions' => decisions }])

    expect(result.dig('groups', 'panel')).to include(
      'agreement_ratio' => 0.7,
      'is_degenerate' => false
    )
    expect(result['actionable_candidate_ids'].count).to eq(7)
  end

  it 'rejects an agreement without reachability evidence' do
    candidates = [candidate('P1', 'panel')]
    adjudication = {
      'source_group' => 'panel',
      'decisions' => [{ 'id' => 'P1', 'decision' => 'AGREE', 'rationale' => 'Looks plausible' }]
    }

    result = validate(candidates, [adjudication])

    expect(result['valid']).to be(false)
    expect(result['errors']).to include(
      'panel.decisions[0].trigger must be a non-empty string',
      'panel.decisions[0].mechanism must be a non-empty string',
      'panel.decisions[0].reachability_source must be a non-empty string',
      'panel.decisions[0].evidence must be a non-empty string'
    )
  end

  it 'rejects unsupported reachability evidence sources' do
    candidates = [candidate('P1', 'panel')]
    row = decision('P1', 'AGREE').merge('reachability_source' => 'absence_of_documentation')

    result = validate(candidates, [{ 'source_group' => 'panel', 'decisions' => [row] }])

    expect(result['valid']).to be(false)
    expect(result['errors'].join).to include('reachability_source must be one of')
  end

  it 'routes needs-context candidates to manual verification' do
    candidates = [candidate('P1', 'panel'), candidate('P2', 'panel')]
    decisions = [decision('P1', 'AGREE'), decision('P2', 'NEEDS_CONTEXT')]

    result = validate(candidates, [{ 'source_group' => 'panel', 'decisions' => decisions }])

    expect(result['requires_manual_verification']).to be(true)
    expect(result['manual_verification_candidate_ids']).to eq(['P2'])
    expect(result['actionable_candidate_ids']).to eq(['P1'])
  end

  it 'rejects missing and unknown candidate decisions' do
    candidates = [candidate('P1', 'panel'), candidate('P2', 'panel')]
    decisions = [decision('P1', 'DISAGREE'), decision('P3', 'DISAGREE')]

    result = validate(candidates, [{ 'source_group' => 'panel', 'decisions' => decisions }])

    expect(result['valid']).to be(false)
    expect(result['errors']).to include(
      'missing decision for candidate P2',
      'unknown decision candidate P3'
    )
  end
end
# rubocop:enable Metrics/BlockLength
