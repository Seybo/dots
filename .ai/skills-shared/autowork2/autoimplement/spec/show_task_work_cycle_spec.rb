# frozen_string_literal: true

require 'json'
require_relative '../../spec/spec_helper'

RSpec.describe 'ShowTaskWorkCycle' do
  let(:service_class) { Object.const_get(:ShowTaskWorkCycle) }
  let(:db) { Database.connection }

  before do
    allow(Database).to receive(:readonly_connection).and_return(db)
  end

  it 'returns persisted Task Work Cycle context as JSON' do
    task_id = db[:tasks].insert(
      created_at: Time.now,
      task_path: '/tasks/0027-task',
      project_path: '/project',
      branch_name: 'feature',
      starting_commit_sha: 'starting-sha',
      state: 'initialized'
    )
    work_cycle_id = db[:work_cycles].insert(
      created_at: Time.now,
      task_id: task_id,
      step_number: 2,
      role: 'worker',
      action: 'implementation'
    )

    context = JSON.parse(service_class.call(work_cycle_id: work_cycle_id))

    expect(context).to eq(
      'work_cycle_id' => work_cycle_id,
      'task_id' => task_id,
      'role' => 'worker',
      'action' => 'implementation',
      'task_path' => '/tasks/0027-task',
      'project_path' => '/project',
      'branch_name' => 'feature',
      'step_number' => 2
    )
  end
end
