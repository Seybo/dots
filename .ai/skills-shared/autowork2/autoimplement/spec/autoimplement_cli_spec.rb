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
    allow(ResumeTask).to receive(:call).and_return('AutoImplementCycle 12')
    allow(ShowTaskWorkCycle).to receive(:call).and_return('{"work_cycle_id":12}')
    allow(WaitTaskWorkCycle).to receive(:call).and_return('Worker implementation completed.')
  end

  it 'initializes or resumes the selected Task and renders it' do
    expect do
      service_class.call(cli_args: ['initialize-task', task_path])
    end.to output("Task: 7\n").to_stdout

    expect(MigrateDatabase).to have_received(:call)
    expect(InitializeTask).to have_received(:call).with(task_path: task_path)
    expect(RenderTask).to have_received(:call).with(task: task)
  end

  it 'resumes one persisted Task' do
    expect do
      service_class.call(cli_args: %w[resume-task 7])
    end.to output("AutoImplementCycle 12\n").to_stdout

    expect(MigrateDatabase).to have_received(:call)
    expect(ResumeTask).to have_received(:call).with(task_id: '7')
  end

  it 'shows one Work Cycle without running migrations' do
    expect do
      service_class.call(cli_args: %w[show-work-cycle 12])
    end.to output("{\"work_cycle_id\":12}\n").to_stdout

    expect(MigrateDatabase).not_to have_received(:call)
    expect(ShowTaskWorkCycle).to have_received(:call).with(work_cycle_id: '12')
  end

  it 'waits for one Work Cycle result' do
    expect do
      service_class.call(cli_args: %w[wait-work-cycle 12])
    end.to output("Worker implementation completed.\n").to_stdout

    expect(MigrateDatabase).to have_received(:call)
    expect(WaitTaskWorkCycle).to have_received(:call).with(work_cycle_id: '12')
  end

  it 'rejects unsupported or malformed commands' do
    [
      [],
      ['initialize-task'],
      ['initialize-task', task_path, 'extra'],
      ['resume-task'],
      %w[resume-task 7 extra],
      ['show-work-cycle'],
      ['wait-work-cycle'],
      %w[other 12],
    ].each do |cli_args|
      expect { service_class.call(cli_args: cli_args) }.
        to raise_error(
          ArgumentError,
          'Usage: autoimplement [initialize-task <canonical-task-path> | resume-task <task-id> | ' \
          'show-work-cycle <id> | wait-work-cycle <id>]'
        )
    end
  end
end
