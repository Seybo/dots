# frozen_string_literal: true

require_relative '../../spec/spec_helper'
require_relative '../app/services/render_task'

RSpec.describe 'RenderTask' do
  let(:service_class) { Object.const_get(:RenderTask) }

  it 'renders stable Task identity and state' do
    task = {
      id: 7,
      task_path: '/tasks/0025-create-autoimplement-work',
      project_path: '/project',
      branch_name: 'feature',
      starting_commit_sha: 'abc123',
      state: 'initialized'
    }

    expect(service_class.call(task: task)).to eq(
      "Task: 7\n" \
      "Task path: /tasks/0025-create-autoimplement-work\n" \
      "Project path: /project\n" \
      "Branch: feature\n" \
      "Starting commit: abc123\n" \
      'State: initialized'
    )
  end
end
