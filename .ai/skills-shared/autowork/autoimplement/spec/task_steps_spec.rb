# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'
require_relative '../../spec/spec_helper'

RSpec.describe 'TaskSteps' do
  let(:service_class) { Object.const_get(:TaskSteps) }
  let(:task_path) { Dir.mktmpdir('task-steps-spec') }

  after do
    FileUtils.remove_entry(task_path)
  end

  it 'reads canonical headings in authored order' do
    File.write(
      File.join(task_path, 'steps.md'),
      <<~MARKDOWN
        # Steps

        ## Step 8: First authored

        Body.

        ### Step 9: Not canonical

        ## Step 2
      MARKDOWN
    )

    expect(service_class.new(task_path: task_path).all).to eq(
      [
        { number: 8, title: 'First authored' },
        { number: 2, title: nil },
      ]
    )
  end

  it 'finds one parsed step by number' do
    File.write(File.join(task_path, 'steps.md'), "## Step 3: Selected\n")

    expect(service_class.new(task_path: task_path).find(3)).to eq(
      number: 3,
      title: 'Selected'
    )
  end
end
