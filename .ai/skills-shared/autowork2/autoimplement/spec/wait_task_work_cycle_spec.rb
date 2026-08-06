# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'tmpdir'
require_relative '../../spec/spec_helper'

RSpec.describe WaitTaskWorkCycle do
  let(:db) { Database.connection }
  let(:task_path) { Dir.mktmpdir('wait-task-work-cycle-spec') }
  let(:task_id) do
    db[:tasks].insert(
      created_at: Time.now,
      task_path: task_path,
      project_path: project_path,
      branch_name: 'feature',
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

  before do
    File.write(
      File.join(task_path, 'steps.md'),
      "# Steps\n\n## Step 1: Build it\n\n## Step 2\n"
    )
    FileUtils.rm_f(result_path)
    allow(CommitWorkCycle).to receive(:call)
  end

  after do
    FileUtils.rm_f(result_path)
    FileUtils.remove_entry(task_path)
  end

  it 'commits a completed step and stores completion provenance' do
    write_result(completed_result)

    output = described_class.call(work_cycle_id: work_cycle_id)

    expect(output).to eq("Worker implementation completed (Cycle #{work_cycle_id}, Step 1).")
    expect(CommitWorkCycle).to have_received(:call).with(
      project_path: project_path,
      message: 'Step 1: Build it'
    )
    expect(db[:work_cycles].where(id: work_cycle_id).first).to include(
      completed_at: be_a(Time),
      provider: 'openai-codex',
      model: 'gpt-5.6-sol',
      reasoning_level: 'high'
    )
    expect(db[:tasks].where(id: task_id).get(:state)).to eq('initialized')
    expect(File.exist?(result_path)).to be(false)
  end

  it 'uses the step number when the authored heading has no title' do
    db[:work_cycles].where(id: work_cycle_id).update(step_number: 2)
    write_result(completed_result)

    described_class.call(work_cycle_id: work_cycle_id)

    expect(CommitWorkCycle).to have_received(:call).with(
      project_path: project_path,
      message: 'Step 2'
    )
  end

  it 'retains a failed result without committing or completing' do
    write_result(completed_result.merge('status' => 'failed', 'error' => 'Could not implement.'))

    expect { described_class.call(work_cycle_id: work_cycle_id) }.
      to raise_error(RuntimeError, "Work Cycle #{work_cycle_id} failed: Could not implement.")

    expect(CommitWorkCycle).not_to have_received(:call)
    expect(db[:work_cycles].where(id: work_cycle_id).get(:completed_at)).to be_nil
    expect(File.exist?(result_path)).to be(true)
  end

  it 'retains a completed result when no managed commit can be created' do
    write_result(completed_result)
    allow(CommitWorkCycle).to receive(:call).and_raise('git commit failed')

    expect { described_class.call(work_cycle_id: work_cycle_id) }.
      to raise_error(RuntimeError, 'git commit failed')

    expect(db[:work_cycles].where(id: work_cycle_id).get(:completed_at)).to be_nil
    expect(File.exist?(result_path)).to be(true)
  end

  def project_path
    '/project'
  end

  def result_path
    "/tmp/autoimplement-work-cycle-#{work_cycle_id}.json"
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
