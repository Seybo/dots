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
end
