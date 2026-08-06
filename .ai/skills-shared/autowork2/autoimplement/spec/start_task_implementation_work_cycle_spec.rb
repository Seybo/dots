# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'
require_relative '../../spec/spec_helper'

RSpec.describe 'StartTaskImplementationWorkCycle' do
  let(:service_class) { Object.const_get(:StartTaskImplementationWorkCycle) }
  let(:db) { Database.connection }
  let(:task_path) { Dir.mktmpdir('start-task-work-cycle-spec') }
  let(:project_path) { '/project' }
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

  before do
    write_steps([8, 2])
    allow(ValidateCleanGitState).to receive(:call).and_return('head-sha')
  end

  after do
    FileUtils.remove_entry(task_path)
  end

  it 'creates one Worker implementation Work Cycle for the first authored step' do
    work_cycle_id = service_class.call(task_id: task_id)

    expect(db[:work_cycles].where(id: work_cycle_id).first).to include(
      task_id: task_id,
      review_id: nil,
      step_number: 8,
      role: 'worker',
      action: 'implementation',
      completed_at: nil
    )
    expect(ValidateCleanGitState).to have_received(:call).with(project_path: project_path)
    expect(db[:tasks].where(id: task_id).get(:state)).to eq('initialized')
  end

  it 'selects the next authored step after a completed implementation' do
    first_work_cycle_id = service_class.call(task_id: task_id)
    db[:work_cycles].where(id: first_work_cycle_id).update(completed_at: Time.now)

    second_work_cycle_id = service_class.call(task_id: task_id)

    expect(db[:work_cycles].where(id: second_work_cycle_id).get(:step_number)).to eq(2)
  end

  it 'returns nil without checking Git when every authored step was implemented' do
    write_steps([1])
    db[:work_cycles].insert(
      created_at: Time.now,
      completed_at: Time.now,
      task_id: task_id,
      step_number: 1,
      role: 'worker',
      action: 'implementation'
    )
    expect(service_class.call(task_id: task_id)).to be_nil

    expect(ValidateCleanGitState).not_to have_received(:call)
    expect(db[:work_cycles].count).to eq(1)
  end

  it 'leaves workflow state unchanged when Git is dirty' do
    allow(ValidateCleanGitState).to receive(:call).and_raise('Working tree is not clean')

    expect { service_class.call(task_id: task_id) }.
      to raise_error(RuntimeError, 'Working tree is not clean')

    expect(db[:work_cycles].count).to eq(0)
    expect(db[:tasks].where(id: task_id).get(:state)).to eq('initialized')
  end

  def write_steps(numbers)
    headings = numbers.map { |number| "## Step #{number}: Step #{number}" }.join("\n\n")
    File.write(File.join(task_path, 'steps.md'), "# Steps\n\n#{headings}\n")
  end
end
