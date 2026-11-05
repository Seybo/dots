# frozen_string_literal: true

require 'rspec'
require 'webmock/rspec'
require_relative '../lib/client'

RSpec.describe 'Listing assigned Linear issues' do
  let(:client) { Linear::Client.new(api_key: 'test-key') }
  let(:issue) do
    { 'id' => 'issue-uuid', 'identifier' => 'HC-123', 'title' => 'Fix', 'url' => 'https://linear.app/x/issue/HC-123/fix',
      'archivedAt' => nil, 'team' => { 'id' => 'team', 'key' => 'HC', 'name' => 'HC' },
      'state' => { 'id' => 'ready', 'name' => 'Ready for Development', 'type' => 'unstarted' } }
  end

  def page(nodes, is_next: false, cursor: nil)
    { 'data' => { 'organization' => { 'urlKey' => 'shakacode' },
                  'viewer' => { 'id' => 'authenticated-user', 'assignedIssues' => {
                    'nodes' => nodes, 'pageInfo' => { 'hasNextPage' => is_next, 'endCursor' => cursor }
                  } } } }
  end

  def response_pages(*pages)
    stub_request(:post, Linear::Client::ENDPOINT).to_return(*pages.map { |data| { body: JSON.generate(data) } })
  end

  it 'lists every page across teams, statuses and archives using the authenticated viewer' do
    done = issue.merge('id' => 'other-uuid', 'identifier' => 'HCD-88', 'archivedAt' => '2026-01-01T00:00:00Z',
                       'team' => { 'id' => 'data', 'key' => 'HCD', 'name' => 'HC Data' },
                       'state' => { 'id' => 'done', 'name' => 'Done', 'type' => 'completed' })
    canceled = done.merge('id' => 'canceled-uuid', 'identifier' => 'MKT-42',
                          'team' => { 'id' => 'content', 'key' => 'MKT', 'name' => 'Content' },
                          'state' => { 'id' => 'canceled', 'name' => 'Canceled', 'type' => 'canceled' })
    response_pages(page([issue], is_next: true, cursor: 'next'), page([done, canceled]))

    expect(client.list_my_issues).to eq('issues' => [issue.merge('is_archived' => false),
                                                     done.merge('is_archived' => true),
                                                     canceled.merge('is_archived' => true)], 'issues_count' => 3)
    expect(WebMock).to(have_requested(:post, Linear::Client::ENDPOINT).with do |request|
      data = JSON.parse(request.body)
      query = data.fetch('query')
      query.include?('viewer {') && query.include?('includeArchived: true') && !query.include?('filter:') &&
        data.fetch('variables') == { 'after' => 'next' }
    end.once)
    expect(WebMock).not_to(have_requested(:post, Linear::Client::ENDPOINT).with do |request|
      JSON.parse(request.body).fetch('query').include?('mutation')
    end)
  end

  it 'returns an empty complete list when the viewer has no assigned issues' do
    response_pages(page([]))
    expect(client.list_my_issues).to eq('issues' => [], 'issues_count' => 0)
  end

  it 'rejects another workspace rather than labeling its results as ShakaCode' do
    data = page([issue])
    data['data']['organization']['urlKey'] = 'other-workspace'
    response_pages(data)
    expect { client.list_my_issues }.to raise_error(Linear::Error, /workspace/)
  end

  it 'rejects missing viewer identity' do
    data = page([issue])
    data['data']['viewer'].delete('id')
    response_pages(data)
    expect { client.list_my_issues }.to raise_error(Linear::Error, /incomplete/)
  end

  it 'fails the whole listing when a later page fails' do
    stub_request(:post, Linear::Client::ENDPOINT)
      .to_return({ body: JSON.generate(page([issue], is_next: true, cursor: 'next')) }, { status: 503 })
    expect { client.list_my_issues }.to raise_error(Linear::Error, /503/)
  end

  it 'rejects partial data accompanied by GraphQL errors' do
    data = page([issue])
    data['errors'] = [{ 'message' => 'Unavailable team' }]
    response_pages(data)
    expect { client.list_my_issues }.to raise_error(Linear::Error, /Unavailable team/)
  end

  [nil, {}, { 'nodes' => [], 'pageInfo' => {} },
   { 'nodes' => [], 'pageInfo' => { 'hasNextPage' => nil } },
   { 'nodes' => [], 'pageInfo' => { 'hasNextPage' => true, 'endCursor' => nil } }].each do |incomplete|
    it "rejects incomplete pagination: #{incomplete.inspect}" do
      data = page([issue])
      data['data']['viewer']['assignedIssues'] = incomplete
      response_pages(data)
      expect { client.list_my_issues }.to raise_error(Linear::Error, /incomplete|pagination/)
    end
  end

  it 'rejects repeated cursors rather than looping or silently stopping' do
    response_pages(page([issue], is_next: true, cursor: 'same'), page([], is_next: true, cursor: 'same'))
    expect { client.list_my_issues }.to raise_error(Linear::Error, /cursor/)
    expect(WebMock).to have_requested(:post, Linear::Client::ENDPOINT).twice
  end

  %w[identifier title url team state archivedAt].each do |field|
    it "rejects an issue with missing #{field} rather than returning an incomplete list" do
      response_pages(page([issue.reject { |key| key == field }]))
      expect { client.list_my_issues }.to raise_error(Linear::Error, /incomplete/)
    end
  end
end
