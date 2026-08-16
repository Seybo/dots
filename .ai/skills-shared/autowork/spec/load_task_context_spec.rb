# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'tmpdir'
require_relative 'spec_helper'

RSpec.describe LoadTaskContext do
  let(:root_path) { Dir.mktmpdir('load-task-context-spec') }
  let(:task_path) { File.join(root_path, 'env', '0046-featured-task') }
  let(:feature_path) { File.join(root_path, 'env', 'features', 'feature-workflow.md') }
  let(:task) { { task_path: task_path, project_path: '/project' } }

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

  it 'returns the complete linked Feature context for a featured Task' do
    FileUtils.mkdir_p(File.dirname(feature_path))
    File.write(feature_path, "# Feature workflow\n\nShared context.\n")
    File.write(
      File.join(task_path, 'task.md'),
      "Feature: [feature-workflow](../features/feature-workflow.md)\n\n# Task\n"
    )

    context = described_class.call(task: task)

    expect(context).to include(
      feature_path: feature_path,
      feature_text: "# Feature workflow\n\nShared context.\n"
    )
  end

  it 'returns nil Feature context without the exact leading reference' do
    File.write(File.join(task_path, 'task.md'), "# Task\n")

    context = described_class.call(task: task)

    expect(context).to include(feature_path: nil, feature_text: nil)
  end
end
