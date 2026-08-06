# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'
require_relative '../../spec/spec_helper'

RSpec.describe 'ResumeTask' do
  let(:service_class) { Object.const_get(:ResumeTask) }
  let(:db) { Database.connection }
  let(:task_path) { Dir.mktmpdir('resume-task-spec') }
  let(:task_id) do
    db[:tasks].insert(
      created_at: Time.now,
      task_path: task_path,
      project_path: '/project',
      branch_name: 'feature',
      starting_commit_sha: 'starting-sha',
      state: 'initialized'
    )
  end

  before do
    File.write(
      File.join(task_path, 'steps.md'),
      "# Steps\n\n## Step 1: First\n\n## Step 2: Second\n"
    )
    allow(ValidateCleanGitState).to receive(:call).and_return('head-sha')
  end

  after do
    FileUtils.remove_entry(task_path)
  end

  it 'creates and renders one new Worker handoff' do
    output = service_class.call(task_id: task_id)
    work_cycle = db[:work_cycles].first

    expect(output).to eq("AutoImplementCycle #{work_cycle.fetch(:id)}")
    expect(work_cycle).to include(task_id: task_id, step_number: 1, completed_at: nil)
  end

  it 'waits for the same incomplete Work Cycle without redispatch or a clean-Git check' do
    first_output = service_class.call(task_id: task_id)
    work_cycle_id = first_output.split.last.to_i
    allow(ValidateCleanGitState).to receive(:call).and_raise('should not run')

    expect(service_class.call(task_id: task_id)).to eq("WaitWorkCycle #{work_cycle_id}")
    expect(db[:work_cycles].count).to eq(1)
  end

  it 'creates the next authored step after the previous implementation completed' do
    first_output = service_class.call(task_id: task_id)
    first_work_cycle_id = first_output.split.last.to_i
    db[:work_cycles].where(id: first_work_cycle_id).update(completed_at: Time.now)

    second_output = service_class.call(task_id: task_id)
    second_work_cycle = db[:work_cycles].order(:id).last

    expect(second_output).to eq("AutoImplementCycle #{second_work_cycle.fetch(:id)}")
    expect(second_work_cycle.fetch(:step_number)).to eq(2)
  end

  it 'reports when no unimplemented step remains' do
    first_output = service_class.call(task_id: task_id)
    first_work_cycle_id = first_output.split.last.to_i
    db[:work_cycles].where(id: first_work_cycle_id).update(completed_at: Time.now)
    second_output = service_class.call(task_id: task_id)
    second_work_cycle_id = second_output.split.last.to_i
    db[:work_cycles].where(id: second_work_cycle_id).update(completed_at: Time.now)

    expect(service_class.call(task_id: task_id)).to eq('No unimplemented Task step.')
    expect(db[:work_cycles].count).to eq(2)
  end
end
