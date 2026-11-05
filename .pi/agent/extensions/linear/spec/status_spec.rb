# frozen_string_literal: true

require 'rspec'
require 'webmock/rspec'
require_relative '../lib/client'

RSpec.describe 'Changing Linear issue status' do
  let(:client) { Linear::Client.new(api_key: 'test-key') }
  let(:target) { { 'id' => 'ready-uuid', 'name' => 'Ready for Development' } }
  let(:issue) do
    { 'id' => 'issue-uuid', 'identifier' => 'HCD-123', 'title' => 'Fix',
      'url' => 'https://linear.app/shakacode/issue/HCD-123/fix', 'branchName' => 'provider/branch',
      'description' => 'Keep this', 'archivedAt' => '2026-01-01T00:00:00Z',
      'state' => { 'id' => 'backlog', 'name' => 'Backlog' },
      'team' => { 'id' => 'data-team', 'key' => 'HCD', 'name' => 'HC Data' } }
  end
  let(:saved) { issue.merge('state' => target) }

  def query_request(fragment)
    stub_request(:post, Linear::Client::ENDPOINT).with do |request|
      JSON.parse(request.body).fetch('query').include?(fragment)
    end
  end

  def readback_request
    stub_request(:post, Linear::Client::ENDPOINT).with do |request|
      data = JSON.parse(request.body)
      data.fetch('query').include?('issue(id:') && data.fetch('variables')['id'] == 'issue-uuid'
    end
  end

  def state_page(nodes, is_next: false, cursor: nil)
    page = { 'nodes' => nodes, 'pageInfo' => { 'hasNextPage' => is_next, 'endCursor' => cursor } }
    JSON.generate('data' => { 'team' => { 'states' => page } })
  end

  def expect_one_status_mutation
    expect(WebMock).to(have_requested(:post, Linear::Client::ENDPOINT).with do |request|
      data = JSON.parse(request.body)
      data.fetch('query').include?('issueUpdate(') &&
        data.fetch('variables') == { 'id' => 'issue-uuid', 'input' => { 'stateId' => 'ready-uuid' } }
    end.once)
  end

  before do
    query_request('issue(id:').to_return(body: JSON.generate('data' => { 'issue' => issue }))
    readback_request.to_return(body: JSON.generate('data' => { 'issue' => saved }))
    query_request('states(').to_return(body: state_page([target]))
    result = { 'data' => { 'issueUpdate' => { 'success' => true, 'issue' => saved } } }
    query_request('issueUpdate(').to_return(body: JSON.generate(result))
  end

  it 'resolves the issue team, updates only stateId, and returns the read-back issue' do
    expect(client.set_issue_status(issue.fetch('url'), 'Ready for Development')).to eq(saved)
    expect_one_status_mutation
    expect(WebMock).to(have_requested(:post, Linear::Client::ENDPOINT).with do |request|
      data = JSON.parse(request.body)
      data.fetch('query').include?('states(') && data.fetch('variables')['id'] == 'data-team'
    end.once)
    expect(WebMock).to(have_requested(:post, Linear::Client::ENDPOINT).with do |request|
      data = JSON.parse(request.body)
      data.fetch('query').include?('issue(id:') && data.fetch('variables')['id'] == 'issue-uuid'
    end.once)
  end

  it 'follows all team status pages before selecting the exact name' do
    query_request('states(').to_return(
      { body: state_page([], is_next: true, cursor: 'next') },
      { body: state_page([target]) }
    )
    expect(client.set_issue_status('HCD-123', target.fetch('name'))).to eq(saved)
    expect_one_status_mutation
  end

  ['Unknown', 'ready for development', ''].each do |name|
    it "rejects an unknown or blank status #{name.inspect} without mutation" do
      expect { client.set_issue_status('HCD-123', name) }.to raise_error(Linear::Error)
      expect(WebMock).not_to(have_requested(:post, Linear::Client::ENDPOINT).with do |request|
        JSON.parse(request.body).fetch('query').include?('mutation')
      end)
    end
  end

  it 'rejects incomplete workflow status identity without mutation' do
    query_request('states(').to_return(body: state_page([target.reject { |key| key == 'id' }]))
    expect { client.set_issue_status('HCD-123', target.fetch('name')) }.to raise_error(Linear::Error, /incomplete/)
    expect(WebMock).not_to(have_requested(:post, Linear::Client::ENDPOINT).with do |request|
      JSON.parse(request.body).fetch('query').include?('mutation')
    end)
  end

  it 'does not mutate when workflow lookup fails' do
    query_request('states(').to_return(status: 503)
    expect { client.set_issue_status('HCD-123', target.fetch('name')) }.to raise_error(Linear::Error, /503/)
    expect(WebMock).not_to(have_requested(:post, Linear::Client::ENDPOINT).with do |request|
      JSON.parse(request.body).fetch('query').include?('mutation')
    end)
  end

  it 'rejects ambiguous status names without mutation' do
    query_request('states(').to_return(body: state_page([target, target.merge('id' => 'duplicate')]))
    expect { client.set_issue_status('HCD-123', target.fetch('name')) }.to raise_error(Linear::Error, /exactly one/)
    expect(WebMock).not_to(have_requested(:post, Linear::Client::ENDPOINT).with do |request|
      JSON.parse(request.body).fetch('query').include?('mutation')
    end)
  end

  it 'does not trust a successful mutation when saved status differs' do
    readback_request.to_return(body: JSON.generate('data' => { 'issue' => issue }))
    expect { client.set_issue_status('HCD-123', target.fetch('name')) }
      .to raise_error(Linear::Error, /could not be verified/)
    expect_one_status_mutation
  end

  it 'reports an unverified change when read-back fails' do
    readback_request.to_return(status: 503)
    expect { client.set_issue_status('HCD-123', target.fetch('name')) }
      .to raise_error(Linear::Error, /could not be verified.*503/)
    expect_one_status_mutation
  end

  it 'rejects incomplete read-back state without claiming success' do
    readback_request.to_return(body: JSON.generate('data' => { 'issue' => saved.reject { |key| key == 'state' } }))
    expect { client.set_issue_status('HCD-123', target.fetch('name')) }
      .to raise_error(Linear::Error, /could not be verified/)
    expect_one_status_mutation
  end

  it 'accepts a matching saved status after a timeout without retrying the mutation' do
    query_request('issueUpdate(').to_timeout
    expect(client.set_issue_status('HCD-123', target.fetch('name'))).to eq(saved)
    expect_one_status_mutation
  end

  it 'stops after a timed-out mutation and mismatching saved status' do
    query_request('issueUpdate(').to_timeout
    readback_request.to_return(body: JSON.generate('data' => { 'issue' => issue }))
    expect { client.set_issue_status('HCD-123', target.fetch('name')) }
      .to raise_error(Linear::Error, /could not be verified/)
    expect_one_status_mutation
  end

  it 'stops when both mutation and verification fail' do
    query_request('issueUpdate(').to_timeout
    readback_request.to_return(status: 503)
    expect { client.set_issue_status('HCD-123', target.fetch('name')) }
      .to raise_error(Linear::Error, /could not be verified.*503/)
    expect_one_status_mutation
  end

  [nil, { 'success' => false }, { 'success' => true, 'issue' => nil }].each do |result|
    it "verifies an uncertain mutation response #{result.inspect} without retrying" do
      query_request('issueUpdate(').to_return(body: JSON.generate('data' => { 'issueUpdate' => result }))
      expect(client.set_issue_status('HCD-123', target.fetch('name'))).to eq(saved)
      expect_one_status_mutation
    end
  end

  it 'inspects a GraphQL mutation failure before reporting an unverified outcome' do
    query_request('issueUpdate(').to_return(body: JSON.generate('errors' => [{ 'message' => 'Permission denied' }]))
    readback_request.to_return(body: JSON.generate('data' => { 'issue' => issue }))
    expect { client.set_issue_status('HCD-123', target.fetch('name')) }
      .to raise_error(Linear::Error, /could not be verified.*Permission denied/)
    expect_one_status_mutation
  end

  it 'inspects a null data mutation response before confirming success' do
    query_request('issueUpdate(').to_return(body: JSON.generate('data' => nil))
    expect(client.set_issue_status('HCD-123', target.fetch('name'))).to eq(saved)
    expect_one_status_mutation
  end
end
