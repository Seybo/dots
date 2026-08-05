# frozen_string_literal: true

require 'tmpdir'
require_relative '../../spec/spec_helper'
require_relative '../app/services/validate_task_files'

RSpec.describe 'ValidateTaskFiles' do
  let(:service_class) { Object.const_get(:ValidateTaskFiles) }
  let(:root_path) { Dir.mktmpdir('validate-task-files-spec') }
  let(:task_path) { File.join(root_path, 'task') }

  before do
    FileUtils.mkdir_p(task_path)
    File.write(File.join(task_path, 'task.md'), "# Context\n")
    File.write(File.join(task_path, 'steps.md'), "# Steps\n\n## Step 1: Start\n")
  end

  after do
    FileUtils.remove_entry(root_path)
  end

  it 'returns the canonical Task path for valid authored files' do
    expect(service_class.call(task_path: task_path)).to eq(File.realpath(task_path))
  end

  it 'requires task.md' do
    FileUtils.rm_f(File.join(task_path, 'task.md'))

    expect { service_class.call(task_path: task_path) }.
      to raise_error("Missing authored Task file: #{File.join(File.realpath(task_path), 'task.md')}")
  end

  it 'requires steps.md' do
    FileUtils.rm_f(File.join(task_path, 'steps.md'))

    expect { service_class.call(task_path: task_path) }.
      to raise_error("Missing authored Task file: #{File.join(File.realpath(task_path), 'steps.md')}")
  end

  it 'requires a canonical step heading' do
    File.write(File.join(task_path, 'steps.md'), "# Steps\n\n## Setup\n")

    expect { service_class.call(task_path: task_path) }.
      to raise_error("No canonical Step heading in #{File.join(File.realpath(task_path), 'steps.md')}")
  end

  it 'requires the Task path to be a directory' do
    file_path = File.join(root_path, 'not-a-directory')
    File.write(file_path, 'task')

    expect { service_class.call(task_path: file_path) }.
      to raise_error("Task path is not a directory: #{file_path}")
  end
end
