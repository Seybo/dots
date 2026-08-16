# frozen_string_literal: true

require_relative '../../spec/spec_helper'

RSpec.describe 'Autofix skill contract' do
  let(:skill) { File.read(File.expand_path('../SKILL.md', __dir__)) }
  let(:decision_policy) do
    File.read(File.expand_path('../../../components/reported-issue-decision-reasons.md', __dir__))
  end

  it 'requires Task resolution before importing Review feedback' do
    expect(skill).to include('../../components/task-resolution.md')
    expect(skill).to match(/Shortcut project.*sc-<digits>.*exactly one Task folder/im)
    expect(skill).to include('/skill:autofix --local --task <task-id>')
    expect(skill).to match(/Never infer a local Task.*newest Task/im)
    expect(skill).to include('`final_checks_passed`')
  end

  it 'passes the canonical Task path to resume and both imports' do
    expect(skill).to include('autofix resume <canonical-task-path>')
    expect(skill).to include(
      'import-github-review /tmp/autofix-github-review.json <canonical-task-path>'
    )
    expect(skill).to include(
      'import-local-review /tmp/autofix-local-review.json <canonical-task-path>'
    )
  end

  it 'uses transient Feature context for inline Manager review' do
    expect(skill).to include('returned `task_path`, `feature_path`, and `feature_text`')
    expect(skill).to include('Task-specific requirements and Reported Issues win conflicts')
    expect(skill).to include('do not perform a Feature lookup')
  end

  it 'rebases the completed Task before import or during one active Review' do
    expect(skill).to include('valid before Review import')
    expect(skill).to match(/while one Review remains incomplete/i)
    expect(skill).to include('rebase-task <canonical-task-path> <base-ref>')
    expect(skill).to include(
      'continue-task-rebase <canonical-task-path> <target-ref> <full-target-sha>'
    )
    expect(skill).to include('AutoFixRebaseConflict <task-id>')
    expect(skill).not_to include('rebase-review <branch>')
    expect(skill).not_to include('continue-review-rebase <branch>')
  end

  it 'shares Manager conflict policy without resuming or reopening Autoimplement' do
    expect(skill).to include('../../components/rebase-conflict-resolution.md')
    expect(skill).to match(/Do not reopen Autoimplement.*rerun final reviews/m)
    expect(skill).to match(/Do not enter \*\*Resume\*\*.*during or after it/m)
    expect(skill).to match(/never offer or invoke it for a local-provider Task/i)
  end

  it 'collects exact reasons through the shared Reported Issue decision policy' do
    expect(skill).to include('../../components/reported-issue-decision-reasons.md')
    expect(skill).to include(
      'store-decision <id> <approved|skipped> <shell-escaped-reason>'
    )
    expect(decision_policy).to match(/store the\s+exact displayed\s+recommendation reason unchanged/i)
    expect(decision_policy).to match(/asks\s+one concise follow-up question and persists nothing/)
    expect(decision_policy).to include('Decision: <approved|skipped>')
    expect(decision_policy).to include('Reason: <exact stored reason>')
    expect(decision_policy).to match(/unambiguous affirmative.*accepts Manager's recommendation/im)
    expect(decision_policy).to match(/paraphrase.*confirm.*understood/m)
    expect(decision_policy).to match(/cannot understand.*persists nothing/m)
    expect(decision_policy).to match(/disagrees.*explicitly.*persists nothing.*confirmation/m)
    expect(decision_policy).to match(/Unclear.*persists nothing.*apply the operator-reasoning rules/m)
  end

  it 'requires repository final-check preflight before importing a new Review' do
    resume_index = skill.index('## Resume')
    preflight_index = skill.index('## Repository final-check preflight')
    github_index = skill.index('## GitHub')

    expect(resume_index).to be < preflight_index
    expect(preflight_index).to be < github_index
    expect(skill).to include('<canonical-checkout>/.autowork.yml')
    expect(skill).to match(/before collecting a\s+new Review source/)
    expect(skill).to include('Agent-manager discovers established commands')
    expect(skill).to include('Ruby never discovers final-check commands')
    expect(skill).to include('separate explicit approval to commit')
    expect(skill).to match(/re-invoke\s+Autofix from the start/)
    expect(skill).to include('no root-`Gemfile` fallback')
  end

  it 'uses the pull request base exactly and keeps local transport base-free' do
    expect(skill).to include('Select exactly `origin/<baseRefName>`')
    expect(skill).to include('{"issues": ["<issue body>"]}')
    expect(skill).not_to include('/skill:autofix --base <ref>')
    expect(skill).not_to include('/skill:autofix --local --base <ref>')
  end
end
