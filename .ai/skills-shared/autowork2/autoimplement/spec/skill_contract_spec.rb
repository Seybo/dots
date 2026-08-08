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

  it 'documents the complete final gate order and one-time reviews' do
    step_index = skill.index('independent Reviewer review for every authored step')
    super_index = skill.index('one whole-task super-review')
    worker_index = skill.index('one whole-task Worker self-review')
    manager_index = skill.index('4. Manager-context review')
    checks_index = skill.index('5. final checks')
    completion_index = skill.index('6. durable completion')

    expect(step_index).to be < super_index
    expect(super_index).to be < worker_index
    expect(worker_index).to be < manager_index
    expect(manager_index).to be < checks_index
    expect(checks_index).to be < completion_index
    expect(skill).to include('exactly once')
    expect(skill).to include('Final review correction N')
    expect(skill).to include('git diff HEAD~1..HEAD')
  end

  it 'runs Manager reviews inline with durable intent and complete history' do
    expect(skill).to include('`manager`/`review`')
    expect(skill).to match(/run it inline in the current Manager conversation/i)
    expect(skill).to include('`task.md` and `steps.md` are authoritative')
    expect(skill).to include('live conversation context')
    expect(skill).to include('complete ordered `history`')
    expect(skill).to include('git -C <canonical-checkout> diff <starting_commit_sha>..HEAD')
    expect(skill).to match(/Do not edit, stage, commit, push, switch branches, or run checks/)
  end

  it 'publishes Manager results atomically and continues the normal lifecycle' do
    expect(skill).to include('/tmp/autoimplement-work-cycle-<id>.json.tmp')
    expect(skill).to include('/tmp/autoimplement-work-cycle-<id>.json')
    expect(skill).to include('reported_issues')
    expect(skill).to include('wait-work-cycle <id>')
    expect(skill).to include('fresh Manager review')
    expect(skill).to include('final_checks_passed')
    expect(skill).to match(/incomplete Manager Work Cycle.*`--retry`/m)
    expect(skill).to match(/retry.*Manager review.*inline/im)
  end

  it 'offers one non-durable local squash after completion' do
    inspect_index = skill.index(
      'git -C <canonical-checkout> log --oneline <starting_commit_sha>..HEAD',
      skill.index('## Optional squash')
    )
    lookup_index = skill.index('current Shortcut story name')
    failure_index = skill.index('abort without fallback or Git mutation')
    ask_index = skill.index('[MM_NTF] Should i squash?')
    helper_index = skill.index('squash-task <task-id> <canonical-checkout> <subject>')

    expect(skill).to include('AutoImplementSquash <task-id>')
    expect(inspect_index).to be < lookup_index
    expect(lookup_index).to be < failure_index
    expect(failure_index).to be < ask_index
    expect(ask_index).to be < helper_index
    expect(skill).to include('Task <task-id>: <folder slug as words>')
    expect(skill).to include('`no`, `skip`, or `leave`')
    expect(skill).to match(/Do not persist the question, answer, pending state, or squash result/)
  end

  it 'keeps omitted recovery and reconciliation behavior unavailable' do
    expect(skill).to include('Do not suppress duplicate concerns')
    expect(skill).to include('Do not persist conversation transcripts')
    expect(skill).to include('Do not validate commit subjects or counts against SQLite')
    expect(skill).to include('never pushes')
  end

  it 'keeps temporary super-review artifacts and workflow database writes constrained' do
    expect(skill).to match(/`super-review\.md` is temporary and\s+non-authoritative/)
    expect(skill).to include('remove it before result publication')
    expect(skill).to match(/Manager remains the\s+only workflow database writer/)
  end
end
