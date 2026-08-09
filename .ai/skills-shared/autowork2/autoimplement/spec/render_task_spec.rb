# frozen_string_literal: true

require 'json'
require 'tmpdir'
require_relative '../../spec/spec_helper'
require_relative '../app/services/render_task'

RSpec.describe 'RenderTask' do
  let(:service_class) { Object.const_get(:RenderTask) }
  let(:root_path) { Dir.mktmpdir('render-task-spec') }
  let(:task_path) { File.join(root_path, 'task') }

  before do
    FileUtils.mkdir_p(task_path)
    File.write(
      File.join(task_path, 'config.json'),
      JSON.generate(
        'branch' => {
          'name' => 'feature',
          'original_base_ref' => 'origin/main',
          'original_base_commit_sha' => 'base-sha',
          'active_base_ref' => 'origin/main',
          'active_base_commit_sha' => 'base-sha'
        }
      )
    )
  end

  after do
    FileUtils.remove_entry(root_path)
  end

  it 'renders stable Task identity and configured branch' do
    task = {
      id: 7,
      task_path: task_path,
      project_path: '/project',
      starting_commit_sha: 'abc123',
      state: 'initialized',
      super_review_agent: 'codex'
    }

    expect(service_class.call(task: task)).to eq(
      "Task: 7\n" \
      "Task path: #{task_path}\n" \
      "Project path: /project\n" \
      "Branch: feature\n" \
      "Starting commit: abc123\n" \
      "State: initialized\n" \
      'Super-review agent: codex'
    )
  end
end
