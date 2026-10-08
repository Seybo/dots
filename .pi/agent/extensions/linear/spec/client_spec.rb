# frozen_string_literal: true

require 'rspec'
require 'webmock/rspec'
require_relative '../lib/client'

RSpec.describe Linear::Client do
  let(:client) { described_class.new(api_key: 'test-key') }
  let(:issue) do
    { 'id' => 'issue-uuid', 'identifier' => 'HC-123', 'title' => 'Fix', 'url' => 'https://linear.app/x/issue/HC-123/fix',
      'branchName' => 'provider/hc-123-fix', 'description' => 'Body', 'team' => { 'id' => 'team', 'key' => 'HC' } }
  end

  def respond(data)
    stub_request(:post, Linear::Client::ENDPOINT).to_return(body: JSON.generate('data' => data))
  end

  it 'reads a URL using GraphQL variables and returns provider identity' do
    respond('issue' => issue)
    expect(client.get_issue(issue.fetch('url'))).to eq(issue)
    expect(WebMock).to(have_requested(:post, Linear::Client::ENDPOINT).with do |request|
      request.headers['Authorization'] == 'test-key' && JSON.parse(request.body)['variables'] == { 'id' => 'HC-123' }
    end)
  end

  it 'does not accept bare numeric selectors' do
    expect { client.get_issue('123') }.to raise_error(Linear::Error, /identifier/)
    expect(WebMock).not_to have_requested(:post, Linear::Client::ENDPOINT)
  end

  it 'creates with destination, type label and viewer assignment' do
    respond('issueCreate' => { 'success' => true, 'issue' => issue })
    destination = { 'team_id' => 'team', 'state_id' => 'ready', 'viewer_id' => 'viewer',
                    'labels' => { 'Bug' => 'bug' }, 'project_id' => 'project' }
    expect(client.create_issue({ 'title' => 'Fix', 'type' => 'Bug' }, destination)).to eq(issue)
    expect(WebMock).to(have_requested(:post, Linear::Client::ENDPOINT).with do |request|
      JSON.parse(request.body)['variables']['input'] == { 'title' => 'Fix', 'teamId' => 'team', 'stateId' => 'ready',
                                                          'assigneeId' => 'viewer', 'labelIds' => ['bug'],
                                                          'projectId' => 'project' }
    end)
  end

  it 'accepts an explicit requester and Markdown while omitting absent Project' do
    respond('issueCreate' => { 'success' => true, 'issue' => issue })
    destination = { 'team_id' => 'team', 'state_id' => 'ready', 'viewer_id' => 'viewer',
                    'labels' => { 'Chore' => 'chore' } }
    client.create_issue({ 'title' => 'Fix', 'type' => 'Chore', 'assignee_id' => 'requester', 'description' => 'Body' },
                        destination)
    expect(WebMock).to(have_requested(:post, Linear::Client::ENDPOINT).with do |request|
      input = JSON.parse(request.body)['variables']['input']
      input['assigneeId'] == 'requester' && input['description'] == 'Body' && !input.key?('projectId')
    end)
  end

  it 'rejects an unknown type and unsupported creation fields before writing' do
    expect { client.create_issue({ 'title' => 'Fix', 'type' => 'Other' }, {}) }.to raise_error(Linear::Error, /type/)
    expect { client.create_issue({ 'title' => 'Fix', 'type' => 'Bug', 'priority' => 1 }, {}) }
      .to raise_error(Linear::Error, /only accepts/)
  end

  it 'updates only title and description by UUID' do
    respond('issueUpdate' => { 'success' => true, 'issue' => issue })
    client.update_issue('issue-uuid', { 'title' => 'Fix', 'description' => 'Body' })
    expect(WebMock).to(have_requested(:post, Linear::Client::ENDPOINT).with do |request|
      JSON.parse(request.body)['variables'] == { 'id' => 'issue-uuid',
                                                 'input' => { 'title' => 'Fix', 'description' => 'Body' } }
    end)
  end

  it 'rejects GraphQL errors even on HTTP success' do
    stub_request(:post,
                 Linear::Client::ENDPOINT).to_return(body: JSON.generate('errors' => [{ 'message' => 'Denied' }]))
    expect { client.get_issue('HC-123') }.to raise_error(Linear::Error, /Denied/)
  end

  it 'rejects unsuccessful or incomplete mutations without retrying' do
    respond('issueCreate' => { 'success' => false })
    destination = { 'team_id' => 'team', 'state_id' => 'ready', 'viewer_id' => 'viewer',
                    'labels' => { 'Bug' => 'bug' } }
    expect { client.create_issue({ 'title' => 'Fix', 'type' => 'Bug' }, destination) }
      .to raise_error(Linear::Error, /inspect Linear before retrying/)
    expect(WebMock).to have_requested(:post, Linear::Client::ENDPOINT).once
  end

  it 'reports a timed-out write as uncertain without retrying' do
    stub_request(:post, Linear::Client::ENDPOINT).to_timeout
    expect { client.update_issue('issue-uuid', { 'description' => 'Body' }) }
      .to raise_error(Linear::Error, /inspect Linear before retrying/)
    expect(WebMock).to have_requested(:post, Linear::Client::ENDPOINT).once
  end

  it 'does not expose the API key in errors' do
    stub_request(:post, Linear::Client::ENDPOINT)
      .to_return(status: 403, body: JSON.generate('errors' => [{ 'message' => 'test-key rejected' }]))
    expect { client.get_issue('HC-123') }.to raise_error(Linear::Error) { |error| expect(error.message).not_to include('test-key') }
  end

  it 'requires credentials' do
    expect { described_class.new(api_key: '').get_issue('HC-123') }.to raise_error(Linear::Error, /LINEAR_API_KEY/)
  end
end
