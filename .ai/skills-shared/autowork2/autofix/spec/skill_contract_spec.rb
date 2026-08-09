# frozen_string_literal: true

require_relative '../../spec/spec_helper'

RSpec.describe 'Autofix skill contract' do
  let(:skill) { File.read(File.expand_path('../SKILL.md', __dir__)) }

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

  it 'uses the pull request base exactly and keeps local transport base-free' do
    expect(skill).to include('Select exactly `origin/<baseRefName>`')
    expect(skill).to include('{"issues": ["<issue body>"]}')
    expect(skill).not_to include('/skill:autofix --base <ref>')
    expect(skill).not_to include('/skill:autofix --local --base <ref>')
  end
end
