# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe 'ValidateProjectWorkflowAvailability' do
  let(:service_class) { Object.const_get(:ValidateProjectWorkflowAvailability) }
  let(:db) { Database.connection }
  let(:project_path) { '/project' }

  it 'rejects Autofix while an Autoimplement Task is active' do
    task_id = insert_task(state: 'initialized')

    expect do
      service_class.call(project_path: project_path, workflow: 'autofix')
    end.to raise_error("Task #{task_id} is already active for #{project_path}: /tasks/1")
  end

  it 'rejects Autoimplement while an Autofix Review is active' do
    task_id = insert_task(state: 'final_checks_passed')
    review_id = insert_review(task_id: task_id, state: 'manager_issues_assessment')

    expect do
      service_class.call(project_path: project_path, workflow: 'autoimplement')
    end.to raise_error("Review #{review_id} is already active for #{project_path}")
  end

  it 'allows work after the other workflow reaches its terminal state' do
    task_id = insert_task(state: 'final_checks_passed')
    insert_review(task_id: task_id, state: 'completed')

    expect do
      service_class.call(project_path: project_path, workflow: 'autofix')
      service_class.call(project_path: project_path, workflow: 'autoimplement')
    end.not_to raise_error
  end

  def insert_task(state:)
    db[:tasks].insert(
      created_at: Time.now,
      task_path: '/tasks/1',
      project_path: project_path,
      starting_commit_sha: 'starting-sha',
      state: state,
      super_review_agent: 'claude'
    )
  end

  def insert_review(task_id:, state:)
    db[:reviews].insert(
      created_at: Time.now,
      completed_at: state == 'completed' ? Time.now : nil,
      number: 1,
      source: 'local',
      starting_commit_sha: 'review-starting-sha',
      state: state,
      task_id: task_id
    )
  end
end
