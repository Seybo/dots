# frozen_string_literal: true

require_relative '../../spec/spec_helper'

RSpec.describe 'Autoimplement Work Cycle prompt' do
  let(:prompt_path) { File.expand_path('../app/prompts/work_cycle.md', __dir__) }
  let(:prompt) { File.read(prompt_path) }

  it 'publishes a complete result through an atomic same-directory rename' do
    expect(prompt).to include('/tmp/autoimplement-work-cycle-<id>.json.tmp')
    expect(prompt).to include('/tmp/autoimplement-work-cycle-<id>.json')
    expect(prompt).to include(
      'mv /tmp/autoimplement-work-cycle-<id>.json.tmp /tmp/autoimplement-work-cycle-<id>.json'
    )
    expect(prompt).to include('Do not create the final result path until the temporary file is complete')
  end

  it 'keeps participant writes outside SQLite and workflow state' do
    expect(prompt).to include('Do not query or write Autoimplement SQLite directly')
    expect(prompt).to include('Do not stage, commit, push, switch branches, or write workflow state')
  end
end
