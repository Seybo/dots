# frozen_string_literal: true

require_relative '../../spec/spec_helper'
require_relative '../app/services/validate_task_files'
require_relative '../app/services/initialize_task'
require_relative '../app/services/render_task'
require_relative '../app/services/autoimplement_cli'

RSpec.describe 'AutoimplementCli' do
  let(:service_class) { Object.const_get(:AutoimplementCli) }
  let(:task_path) { '/tasks/0025-create-autoimplement-work' }
  let(:task) do
    {
      id: 7,
      task_path: task_path,
      project_path: '/project',
      branch_name: 'feature',
      starting_commit_sha: 'abc123',
      state: 'initialized'
    }
  end

  before do
    allow(MigrateDatabase).to receive(:call)
    allow(InitializeTask).to receive(:call).and_return(task)
    allow(RenderTask).to receive(:call).and_return('Task: 7')
  end

  it 'initializes or resumes the selected Task and renders it' do
    expect do
      service_class.call(cli_args: ['initialize-task', task_path])
    end.to output("Task: 7\n").to_stdout

    expect(MigrateDatabase).to have_received(:call)
    expect(InitializeTask).to have_received(:call).with(task_path: task_path)
    expect(RenderTask).to have_received(:call).with(task: task)
  end

  it 'rejects unsupported or malformed commands' do
    [
      [],
      ['initialize-task'],
      ['initialize-task', task_path, 'extra'],
      ['resume-task', task_path],
    ].each do |cli_args|
      expect { service_class.call(cli_args: cli_args) }.
        to raise_error(ArgumentError, 'Usage: autoimplement initialize-task <canonical-task-path>')
    end
  end
end
