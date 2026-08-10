# frozen_string_literal: true

require 'json'
require 'tmpdir'
require_relative 'spec_helper'

RSpec.describe ValidateWorkCycleResult do
  let(:db) { Database.connection }
  let(:result_dir) { Dir.mktmpdir('validate-work-cycle-result-spec') }
  let(:result_path) { File.join(result_dir, 'result.json') }
  let(:task_id) do
    db[:tasks].insert(
      created_at: Time.now,
      task_path: '/task',
      project_path: '/project',
      starting_commit_sha: 'starting-sha',
      state: 'initialized'
    )
  end
  let(:work_cycle_id) do
    db[:work_cycles].insert(
      created_at: Time.now,
      task_id: task_id,
      step_number: 1,
      role: 'worker',
      action: 'implementation'
    )
  end

  after do
    FileUtils.remove_entry(result_dir)
  end

  it 'returns a structurally valid failed result for caller-specific handling' do
    result = valid_result.merge('status' => 'failed', 'error' => 'Could not finish.')
    File.write(result_path, JSON.generate(result))

    expect(described_class.call(work_cycle_id: work_cycle_id, result_path: result_path)).to eq(result)
  end

  it 'preserves existing identity and status validation errors' do
    File.write(result_path, JSON.generate(valid_result.merge('role' => 'reviewer')))
    expect do
      described_class.call(work_cycle_id: work_cycle_id, result_path: result_path)
    end.to raise_error(RuntimeError, "Work Cycle result role does not match Work Cycle #{work_cycle_id}")

    File.write(result_path, JSON.generate(valid_result.merge('status' => 'pending')))
    expect do
      described_class.call(work_cycle_id: work_cycle_id, result_path: result_path)
    end.to raise_error(RuntimeError, 'Unsupported Work Cycle result status: pending')
  end

  private

  def valid_result
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
end
