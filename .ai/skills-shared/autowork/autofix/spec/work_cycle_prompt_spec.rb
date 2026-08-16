# frozen_string_literal: true

require_relative '../../spec/spec_helper'

RSpec.describe 'Autofix Work Cycle prompt' do
  let(:prompt_path) { File.expand_path('../app/prompts/work_cycle.md', __dir__) }
  let(:prompt) { File.read(prompt_path) }

  it 'uses returned Feature context without persisting or rediscovering it' do
    expect(prompt).to include('returned `task_path`')
    expect(prompt).to include('returned `feature_path` and `feature_text`')
    expect(prompt).to include('let Task-specific inputs and requirements win conflicts')
    expect(prompt).to include('do not treat the Feature inventory as requirements')
    expect(prompt).to include('do not perform a Feature lookup')
  end
end
