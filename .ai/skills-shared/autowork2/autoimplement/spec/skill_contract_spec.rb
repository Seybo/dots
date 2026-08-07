# frozen_string_literal: true

require_relative '../../spec/spec_helper'

RSpec.describe 'Autoimplement skill contract' do
  let(:skill_path) { File.expand_path('../SKILL.md', __dir__) }
  let(:skill) { File.read(skill_path) }

  it 'accepts one explicit retry flag through normal Task resolution' do
    expect(skill).to include('/skill:autoimplement --retry')
    expect(skill).to include('/skill:autoimplement <task_id> --retry')
    expect(skill).to include('Reject duplicate `--retry` flags')
    expect(skill).to match(/remove it before applying the\s+existing argument parser/)
  end

  it 'asks Ruby to authorize retry before participant handoff' do
    initialize_index = skill.index('initialize-task <canonical-task-path>')
    retry_index = skill.index('retry-task <id>')
    handoff_index = skill.index('follow **Work Cycle handoff** for its returned `AutoImplementCycle <id>`')

    expect(initialize_index).to be < retry_index
    expect(retry_index).to be < handoff_index
    expect(skill).to match(/do not run `resume-task` on the retry\s+path/i)
  end

  it 'keeps every omitted runtime control unavailable' do
    expect(skill).to include('Do not add status, doctor, pause, limit, lock, or timeout options')
    expect(skill).to match(/Never retry or\s+redispatch automatically/)
  end

  it 'stops at the durable final-check result without participant work' do
    expect(skill).to include('Task <id> final checks passed.')
    expect(skill).to include('the durable `final_checks_passed` state')
    expect(skill).to match(/return the output and stop successfully\s+without contacting a participant/)
    expect(skill).to include('A skipped no-root-`Gemfile` result is passing')
  end

  it 'keeps final-check failure on the Autofix-compatible resume path' do
    failure_contract = Regexp.new(
      'Do\s+not create or assess a Reported Issue, contact a participant, start a correction,' \
      '\s+or retry automatically'
    )

    expect(skill).to match(failure_contract)
    expect(skill).to match(/normal Autoimplement invocation runs\s+`resume-task` and reruns the complete check set/)
    expect(skill).to match(/Explicit `--retry` remains only\s+for an incomplete participant Work Cycle/)
  end
end
