# frozen_string_literal: true

require 'rspec'
require 'webmock/rspec'
require_relative '../lib/client'

RSpec.describe 'Creating Linear sub-issues' do
  let(:client) { Linear::Client.new(api_key: 'test-key') }
  let(:parent) do
    { 'id' => 'parent-uuid', 'identifier' => 'HC-503', 'title' => 'Parent', 'description' => '',
      'url' => 'https://linear.app/shakacode/issue/HC-503/parent', 'branchName' => 'provider/parent',
      'team' => { 'id' => 'other-team', 'key' => 'HC' } }
  end
  let(:child) do
    { 'id' => 'child-uuid', 'identifier' => 'HCD-123', 'title' => 'Child', 'description' => 'Body',
      'url' => 'https://linear.app/shakacode/issue/HCD-123/child', 'branchName' => 'provider/child',
      'parent' => parent.slice('id', 'identifier', 'url') }
  end
  let(:destination) do
    { 'team_id' => 'team', 'state_id' => 'ready', 'viewer_id' => 'viewer', 'labels' => { 'Feature' => 'feature' } }
  end
  let(:params) { { 'title' => 'Child', 'type' => 'Feature', 'parent' => 'HC-503' } }

  def parent_request
    stub_request(:post, Linear::Client::ENDPOINT).with do |request|
      JSON.parse(request.body).fetch('query').include?('issue(id:')
    end
  end

  def create_request
    stub_request(:post, Linear::Client::ENDPOINT).with do |request|
      JSON.parse(request.body).fetch('query').include?('issueCreate(')
    end
  end

  before do
    parent_request.to_return(body: JSON.generate('data' => { 'issue' => parent }))
    create_request.to_return(body: JSON.generate('data' => { 'issueCreate' => { 'success' => true,
                                                                                'issue' => child } }))
  end

  it 'resolves an existing parent and creates the child with its UUID in the same mutation' do
    expect(client.create_issue(params, destination)).to eq(child)
    expect(WebMock).to(have_requested(:post, Linear::Client::ENDPOINT).with do |request|
      data = JSON.parse(request.body)
      data.fetch('query').include?('issueCreate(') && data.fetch('variables').fetch('input') == {
        'title' => 'Child', 'teamId' => 'team', 'stateId' => 'ready',
        'assigneeId' => 'viewer', 'labelIds' => ['feature'], 'parentId' => 'parent-uuid'
      }
    end.once)
  end

  it 'accepts a parent URL, including a parent from another accessible team' do
    expect(client.create_issue(params.merge('parent' => parent.fetch('url')), destination)).to eq(child)
    expect(WebMock).to(have_requested(:post, Linear::Client::ENDPOINT).with do |request|
      data = JSON.parse(request.body)
      data.fetch('query').include?('issue(id:') && data.fetch('variables') == { 'id' => 'HC-503' }
    end.once)
  end

  it 'does not create an issue when parent lookup fails' do
    parent_request.to_return(status: 404)
    expect { client.create_issue(params, destination) }.to raise_error(Linear::Error, /404/)
    expect(WebMock).not_to(have_requested(:post, Linear::Client::ENDPOINT).with do |request|
      JSON.parse(request.body).fetch('query').include?('mutation')
    end)
  end

  it 'rejects bare numeric and blank parent selectors before mutation' do
    ['503', ''].each do |selector|
      expect { client.create_issue(params.merge('parent' => selector), destination) }
        .to raise_error(Linear::Error, /identifier/)
    end
    expect(WebMock).not_to(have_requested(:post, Linear::Client::ENDPOINT).with do |request|
      JSON.parse(request.body).fetch('query').include?('mutation')
    end)
  end

  [nil, { 'id' => 'wrong-parent' }].each do |unexpected|
    it "reports the created issue without retrying when returned parent is #{unexpected.inspect}" do
      result = child.merge('parent' => unexpected)
      create_request.to_return(body: JSON.generate('data' => { 'issueCreate' => { 'success' => true,
                                                                                  'issue' => result } }))
      expect { client.create_issue(params, destination) }
        .to raise_error(Linear::Error, /Created HCD-123.*parent.*Do not recreate/)
      expect(WebMock).to(have_requested(:post, Linear::Client::ENDPOINT).with do |request|
        JSON.parse(request.body).fetch('query').include?('issueCreate(')
      end.once)
    end
  end

  it 'does not retry a timed-out sub-issue creation' do
    create_request.to_timeout
    expect { client.create_issue(params, destination) }.to raise_error(Linear::Error, /inspect Linear before retrying/)
    expect(WebMock).to(have_requested(:post, Linear::Client::ENDPOINT).with do |request|
      JSON.parse(request.body).fetch('query').include?('issueCreate(')
    end.once)
  end
end
