# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe 'StoreReview' do
  let(:db) { Database.connection }
  let(:project_path) { '/project' }

  it 'rejects Review creation atomically while an Autoimplement Task is active' do
    completed_task_id = insert_task(task_path: '/tasks/completed', state: 'final_checks_passed')
    active_task_id = insert_task(task_path: '/tasks/active', state: 'initialized')

    expect do
      StoreReview.call(
        task_context: { task: db[:tasks].where(id: completed_task_id).first },
        source: 'local',
        starting_commit_sha: 'review-starting-sha',
        issue_data: [{ source_id: nil, body: 'Review issue.' }]
      )
    end.to raise_error(
      "Task #{active_task_id} is already active for #{project_path}: /tasks/active"
    )
    expect(db[:reviews].count).to eq(0)
    expect(db[:reported_issues].count).to eq(0)
  end

  def insert_task(task_path:, state:)
    db[:tasks].insert(
      created_at: Time.now,
      task_path: task_path,
      project_path: project_path,
      starting_commit_sha: 'starting-sha',
      state: state,
      super_review_agent: 'claude'
    )
  end
end
