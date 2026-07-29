# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe ReviewCommentUrl do
  it 'extracts the repository and comment ID from an inline review comment URL' do
    url = described_class.new('https://github.com/example/project/pull/123#discussion_r456')

    expect(url.repository).to eq('example/project')
    expect(url.comment_id).to eq('456')
  end

  it 'rejects unsupported input forms' do
    unsupported_values = [
      'https://github.com/example/project/pull/123',
      'https://github.com/example/project/pull/123#pullrequestreview-456',
      '456',
      'comments from reviewer',
    ]

    unsupported_values.each do |value|
      expect { described_class.new(value) }.to raise_error(ArgumentError)
    end
  end
end
