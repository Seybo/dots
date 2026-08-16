# frozen_string_literal: true

require_relative '../../spec/spec_helper'

RSpec.describe 'Autoimplement Work Cycle prompt' do
  let(:prompt_path) { File.expand_path('../app/prompts/work_cycle.md', __dir__) }
  let(:prompt) { File.read(prompt_path) }
  let(:super_review_skill_path) { File.expand_path('../../../super-review/SKILL.md', __dir__) }
  let(:super_review_skill) { File.read(super_review_skill_path) }

  it 'publishes a complete result through an atomic same-directory rename' do
    expect(prompt).to include('/tmp/autoimplement-work-cycle-<id>.json.tmp')
    expect(prompt).to include('/tmp/autoimplement-work-cycle-<id>.json')
    expect(prompt).to include(
      'mv /tmp/autoimplement-work-cycle-<id>.json.tmp /tmp/autoimplement-work-cycle-<id>.json'
    )
    expect(prompt).to include('Do not create the final result path until the temporary file is complete')
  end

  it 'uses returned Feature context without persisting or rediscovering it' do
    expect(prompt).to include('returned `feature_path` and `feature_text`')
    expect(prompt).to include('let `task.md` and `steps.md` win conflicts')
    expect(prompt).to include('do not treat the Feature inventory as requirements')
    expect(prompt).to include('do not perform a Feature lookup')
  end

  it 'distinguishes authored-step and whole-task correction scope' do
    expect(prompt).to include('scope` is `step_implementation`')
    expect(prompt).to include('scope` is `whole_task_correction`')
    expect(prompt).to include('do not locate or limit the correction to one authored step')
  end

  it 'runs one defect-only whole-task final Worker self-review' do
    expect(prompt).to include('## Final Worker self-review')
    expect(prompt).to include('scope` is `final_worker_review`')
    expect(prompt).to include('git -C <project_path> diff <starting_commit_sha>..HEAD')
    expect(prompt).to include('Do not report style, nits, speculative improvements')
    expect(prompt).to include('A completed Worker, Reviewer, or Manager review result also contains')
  end

  it 'runs the authorized whole-task super-review with persisted scope and agent' do
    expect(prompt).to include('scope` is `super_review`')
    expect(prompt).to include('explicit authorization to run the shared super-review workflow')
    expect(prompt).to include('`<starting_commit_sha>..HEAD`')
    expect(prompt).to include('returned `super_review_agent`')
    expect(prompt).to include('remove the generated human report before publishing the Work Cycle result')
  end

  it 'authorizes non-interactive super-review from the persisted Work Cycle only' do
    expect(super_review_skill).to include('AutoImplementCycle <id>')
    expect(super_review_skill).to include('scope: `super_review`')
    expect(super_review_skill).to include('Autoimplement mode stops review output after Phase 3.5')
    expect(super_review_skill).to include('always performs Phase 5 temporary-worktree cleanup')
  end

  it 'reviews exactly one whole-task correction commit' do
    expect(prompt).to include('scope` is `whole_task_correction_review`')
    expect(prompt).to include('git -C <project_path> diff HEAD~1..HEAD')
    expect(prompt).to include(
      'report it only when an approved input remains unresolved or the correction introduced it'
    )
    expect(prompt).to include('exclude every unrelated defect that already existed before the correction')
  end

  it 'defines the inline whole-Task Manager review result' do
    expect(prompt).to include('## Manager review')
    expect(prompt).to include('scope` is `manager_review`')
    expect(prompt).to include('complete ordered `history`')
    expect(prompt).to include('live Manager conversation context when available')
    expect(prompt).to include('`task.md` and `steps.md` remain authoritative')
    expect(prompt).to include('Do not suppress a concern because history contains a similar concern')
    expect(prompt).to include('A completed Worker, Reviewer, or Manager review result also contains')
  end

  it 'keeps participant writes outside SQLite and workflow state' do
    expect(prompt).to include('Do not query or write Autoimplement SQLite directly')
    expect(prompt).to include('Do not stage, commit, push, switch branches, or write workflow state')
  end
end
