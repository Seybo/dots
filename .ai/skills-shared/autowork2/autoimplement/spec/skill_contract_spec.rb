# frozen_string_literal: true

require_relative '../../spec/spec_helper'

RSpec.describe 'Autoimplement skill contract' do
  let(:skill_path) { File.expand_path('../SKILL.md', __dir__) }
  let(:skill) { File.read(skill_path) }

  it 'accepts one explicit retry flag through normal Task resolution' do
    expect(skill).to include('/skill:autoimplement --retry')
    expect(skill).to include('/skill:autoimplement <task_id> --retry')
    expect(skill).to include('Reject duplicate `--retry` flags')
    expect(skill).to include('remove `--retry`')
    expect(skill).to include('existing Task argument parser')
  end

  it 'accepts one persisted super-review agent selection through Task resolution' do
    expect(skill).to include('--super-review-agent claude|codex')
    expect(skill).to include('Reject duplicate `--super-review-agent` flags')
    expect(skill).to match(/remove the flag and its value before\s+applying the existing Task argument parser/)
    expect(skill).to include('initialize-task <canonical-task-path> <claude|codex>')
    expect(skill).to match(/Pass the selection only to `initialize-task`/)
  end

  it 'asks Ruby to authorize retry before participant handoff' do
    initialize_index = skill.index('initialize-task <canonical-task-path>')
    retry_index = skill.index('retry-task <id>')
    handoff_index = skill.index('Then follow **Work Cycle handoff**')

    expect(initialize_index).to be < retry_index
    expect(retry_index).to be < handoff_index
    expect(skill).to match(/do not run `resume-task` on the retry\s+path/i)
  end

  it 'keeps every omitted runtime control unavailable' do
    expect(skill).to match(/Do not add status, doctor, pause, limit, lock, or\s+timeout options/)
    expect(skill).to match(/Never retry or redispatch\s+automatically/)
  end

  it 'routes final Worker review Work Cycles to the Worker pane' do
    expect(skill).to include('`worker`/`review`')
    expect(skill).to include('`worker` → `agent-worker`')
  end

  it 'documents the final gate order through the pending Manager boundary' do
    step_index = skill.index('independent Reviewer review for every authored step')
    super_index = skill.index('one whole-task super-review')
    worker_index = skill.index('one whole-task Worker self-review')
    manager_index = skill.index('pending Manager-context boundary')

    expect(step_index).to be < super_index
    expect(super_index).to be < worker_index
    expect(worker_index).to be < manager_index
    expect(skill).to include('exactly once')
    expect(skill).to include('Final review correction N')
    expect(skill).to include('git diff HEAD~1..HEAD')
  end

  it 'stops at the pending Manager boundary and defers final checks' do
    expect(skill).to include('Task <id> ready for Manager-context review.')
    expect(skill).to include('Final checks are deferred')
    expect(skill).to match(/must not run\s+`RunTaskFinalChecks`/)
    expect(skill).to match(/stop successfully without contacting a\s+participant/)
  end

  it 'keeps temporary super-review artifacts and workflow database writes constrained' do
    expect(skill).to match(/`super-review\.md` is temporary and\s+non-authoritative/)
    expect(skill).to include('remove it before result publication')
    expect(skill).to match(/Manager remains the\s+only workflow database writer/)
  end
end
