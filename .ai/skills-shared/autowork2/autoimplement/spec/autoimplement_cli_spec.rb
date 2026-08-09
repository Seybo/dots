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
      starting_commit_sha: 'abc123',
      state: 'initialized',
      super_review_agent: 'claude'
    }
  end

  before do
    allow(MigrateDatabase).to receive(:call)
    allow(InitializeTask).to receive(:call).and_return(task)
    allow(RenderTask).to receive(:call).and_return('Task: 7')
    allow(ResumeTask).to receive(:call).and_return('AutoImplementCycle 12')
    allow(RetryTaskWorkCycle).to receive(:call).and_return('AutoImplementCycle 12')
    allow(ShowTaskWorkCycle).to receive(:call).and_return('{"work_cycle_id":12}')
    allow(WaitTaskWorkCycle).to receive(:call).and_return('Worker implementation completed.')
    allow(HandleTaskDecision).to receive(:call).and_return('Decision: approved')
    allow(SquashTask).to receive(:call).and_return('Task 7 squashed locally.')
    allow(RebaseTask).to receive(:call).and_return('Task 7 rebased.')
    allow(ContinueTaskRebase).to receive(:call).and_return('Task 7 rebased.')
    allow(ResolveProjectPath).to receive(:call).and_return('/canonical/project')
  end

  it 'initializes or resumes the selected Task and renders it' do
    expect do
      service_class.call(cli_args: ['initialize-task', task_path])
    end.to output("Task: 7\n").to_stdout

    expect(MigrateDatabase).to have_received(:call)
    expect(InitializeTask).to have_received(:call).with(task_path: task_path)
    expect(RenderTask).to have_received(:call).with(task: task)
  end

  it 'initializes with an explicit super-review agent' do
    expect do
      service_class.call(cli_args: ['initialize-task', task_path, 'codex'])
    end.to output("Task: 7\n").to_stdout

    expect(InitializeTask).to have_received(:call).with(
      task_path: task_path,
      super_review_agent: 'codex'
    )
  end

  it 'resumes one persisted Task' do
    expect do
      service_class.call(cli_args: %w[resume-task 7])
    end.to output("AutoImplementCycle 12\n").to_stdout

    expect(MigrateDatabase).to have_received(:call)
    expect(ResumeTask).to have_received(:call).with(task_id: '7')
  end

  it 'retries one persisted Task Work Cycle' do
    expect do
      service_class.call(cli_args: %w[retry-task 7])
    end.to output("AutoImplementCycle 12\n").to_stdout

    expect(MigrateDatabase).to have_received(:call)
    expect(RetryTaskWorkCycle).to have_received(:call).with(task_id: '7')
  end

  it 'stores one Task Reported Issue decision with its exact reason' do
    reason = 'The value is lost; punctuation remains.'

    expect do
      service_class.call(cli_args: ['store-decision', '4', 'approved', reason])
    end.to output("Decision: approved\n").to_stdout

    expect(MigrateDatabase).to have_received(:call)
    expect(HandleTaskDecision).to have_received(:call).with(
      issue_id: '4',
      decision: 'approved',
      reason: reason
    )
  end

  it 'squashes one completed Task with an explicit checkout and subject' do
    expect do
      service_class.call(
        cli_args: ['squash-task', '7', '/canonical/project', 'Current Shortcut story name']
      )
    end.to output("Task 7 squashed locally.\n").to_stdout

    expect(MigrateDatabase).to have_received(:call)
    expect(SquashTask).to have_received(:call).with(
      task_id: '7',
      project_path: '/canonical/project',
      subject: 'Current Shortcut story name'
    )
  end

  it 'starts a Task rebase with an optional exact base ref' do
    expect do
      service_class.call(cli_args: ['rebase-task', task_path, 'origin/release'])
    end.to output("Task 7 rebased.\n").to_stdout

    expect(RebaseTask).to have_received(:call).with(
      task_path: task_path,
      project_path: '/canonical/project',
      base_ref: 'origin/release'
    )
    expect(ResumeTask).not_to have_received(:call)
  end

  it 'continues a Task rebase with retained target metadata' do
    expect do
      service_class.call(
        cli_args: ['continue-task-rebase', task_path, 'origin/main', 'target-sha']
      )
    end.to output("Task 7 rebased.\n").to_stdout

    expect(ContinueTaskRebase).to have_received(:call).with(
      task_path: task_path,
      project_path: '/canonical/project',
      target_base_ref: 'origin/main',
      target_base_commit_sha: 'target-sha'
    )
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
      ['initialize-task', task_path, 'codex', 'extra'],
      ['resume-task'],
      %w[resume-task 7 extra],
      ['retry-task'],
      %w[retry-task 7 extra],
      ['show-work-cycle'],
      ['wait-work-cycle'],
      ['store-decision'],
      %w[store-decision 4],
      %w[store-decision 4 approved],
      %w[store-decision 4 approved reason extra],
      ['squash-task'],
      %w[squash-task 7 /project],
      %w[squash-task 7 /project subject extra],
      ['rebase-task'],
      %w[rebase-task /task origin/main extra],
      %w[continue-task-rebase /task origin/main target-sha extra],
      %w[other 12],
    ].each do |cli_args|
      expect { service_class.call(cli_args: cli_args) }.
        to raise_error(
          ArgumentError,
          'Usage: autoimplement [initialize-task <canonical-task-path> [super-review-agent] | ' \
          'resume-task <task-id> | ' \
          'retry-task <task-id> | store-decision <issue-id> <decision> <reason> | ' \
          'squash-task <task-id> <canonical-project-path> <subject> | ' \
          'rebase-task <canonical-task-path> [base-ref] | ' \
          'continue-task-rebase <canonical-task-path> <target-ref> <target-sha> | ' \
          'show-work-cycle <id> | wait-work-cycle <id>]'
        )
    end
  end
end
