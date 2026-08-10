# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'tmpdir'
require_relative 'spec_helper'

RSpec.describe WaitWorkCycleResult do
  let(:db) { Database.connection }
  let(:result_dir) { Dir.mktmpdir('wait-work-cycle-result-spec') }
  let(:result_path) { File.join(result_dir, 'result.json') }
  let(:review_id) do
    ReviewFactory.insert(
      project_path: '/project',
      branch_name: 'feature',
      starting_commit_sha: 'starting-sha',
      base_ref: 'origin/main',
      base_commit_sha: 'base-sha',
      state: 'worker_implementation'
    )
  end
  let(:work_cycle_id) do
    db[:work_cycles].insert(
      created_at: Time.now,
      review_id: review_id,
      role: 'worker',
      action: 'implementation'
    )
  end

  after do
    FileUtils.remove_entry(result_dir)
  end

  it 'returns one valid completed result without deleting its transport' do
    result = completed_result
    write_result(result)

    expect(described_class.call(work_cycle_id: work_cycle_id, result_path: result_path)).to eq(result)
    expect(File.exist?(result_path)).to be(true)
  end

  it 'raises a failed result without deleting its transport' do
    write_result(completed_result.merge('status' => 'failed', 'error' => 'Could not finish.'))

    expect do
      described_class.call(work_cycle_id: work_cycle_id, result_path: result_path)
    end.to raise_error(RuntimeError, "Work Cycle #{work_cycle_id} failed: Could not finish.")
    expect(File.exist?(result_path)).to be(true)
  end

  it 'retains malformed JSON' do
    File.write(result_path, '{')

    expect do
      described_class.call(work_cycle_id: work_cycle_id, result_path: result_path)
    end.to raise_error(JSON::ParserError)
    expect(File.exist?(result_path)).to be(true)
  end

  it 'rejects mismatched Work Cycle identity' do
    [
      { 'work_cycle_id' => work_cycle_id + 1 },
      { 'role' => 'reviewer' },
      { 'action' => 'review' },
    ].each do |mismatch|
      write_result(completed_result.merge(mismatch))

      expect do
        described_class.call(work_cycle_id: work_cycle_id, result_path: result_path)
      end.to raise_error(RuntimeError, /does not match Work Cycle #{work_cycle_id}/)
    end
  end

  it 'rejects an unsupported result status' do
    write_result(completed_result.merge('status' => 'pending'))

    expect do
      described_class.call(work_cycle_id: work_cycle_id, result_path: result_path)
    end.to raise_error(RuntimeError, 'Unsupported Work Cycle result status: pending')
    expect(File.exist?(result_path)).to be(true)
  end

  def completed_result
    {
      'work_cycle_id' => work_cycle_id,
      'role' => 'worker',
      'action' => 'implementation',
      'status' => 'completed',
      'provider' => 'openai-codex',
      'model' => 'gpt-5.6-sol',
      'reasoning_level' => 'high'
    }
  end

  def write_result(result)
    File.write(result_path, JSON.generate(result))
  end
end
