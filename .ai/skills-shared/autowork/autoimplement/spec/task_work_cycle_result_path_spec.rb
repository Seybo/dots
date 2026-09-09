# frozen_string_literal: true

require_relative '../../spec/spec_helper'

RSpec.describe TaskWorkCycleResultPath do
  around do |example|
    original_result_dir = ENV.delete('AUTOWORK_RESULT_DIR')
    example.run
  ensure
    original_result_dir.nil? ? ENV.delete('AUTOWORK_RESULT_DIR') : ENV['AUTOWORK_RESULT_DIR'] = original_result_dir
  end

  it 'requires a configured result directory' do
    expect { described_class.call(work_cycle_id: 42) }.
      to raise_error(KeyError, /AUTOWORK_RESULT_DIR/)
  end

  it 'uses the configured result directory' do
    ENV['AUTOWORK_RESULT_DIR'] = '/shared/results'

    expect(described_class.call(work_cycle_id: 42)).to eq('/shared/results/autoimplement-work-cycle-42.json')
  end
end
