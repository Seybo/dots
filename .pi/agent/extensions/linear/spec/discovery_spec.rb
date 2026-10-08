# frozen_string_literal: true

require 'rspec'
require 'webmock/rspec'
require_relative '../lib/client'

RSpec.describe 'Linear destination discovery' do
  let(:client) { Linear::Client.new(api_key: 'test-key') }
  let(:config) { { 'workspace' => 'shakacode', 'team' => 'HC', 'status' => 'Ready for Development' } }

  before do
    stub_request(:post, Linear::Client::ENDPOINT).to_return do |request|
      query = JSON.parse(request.body).fetch('query')
      page = { 'pageInfo' => { 'hasNextPage' => false, 'endCursor' => nil } }
      data = if query.include?('organization')
               { 'viewer' => { 'id' => 'viewer' }, 'organization' => { 'urlKey' => 'shakacode' } }
             elsif query.include?('teams(')
               { 'teams' => page.merge('nodes' => [{ 'id' => 'team', 'name' => 'HC', 'key' => 'HC' }]) }
             elsif query.include?('states(')
               { 'team' => { 'states' => page.merge('nodes' => [{ 'id' => 'ready',
                                                                  'name' => 'Ready for Development' }]) } }
             elsif query.include?('labels(')
               nodes = Linear::Client::TYPES.map { |type| { 'id' => type.downcase, 'name' => type } }
               { 'team' => { 'labels' => page.merge('nodes' => nodes) } }
             else
               { 'team' => { 'projects' => page.merge('nodes' => [{ 'id' => 'project', 'name' => 'Optional' }]) } }
             end
      { body: JSON.generate('data' => data) }
    end
  end

  it 'verifies workspace/team/status and resolves existing type labels' do
    destination = client.discover(config)
    expect(destination).to include('team_id' => 'team', 'state_id' => 'ready', 'viewer_id' => 'viewer')
    expect(destination.fetch('labels')).to eq('Bug' => 'bug', 'Feature' => 'feature',
                                              'Improvement' => 'improvement', 'Chore' => 'chore')
    expect(destination).not_to have_key('project_id')
  end

  it 'uses a configured Project only through the selected team' do
    expect(client.discover(config.merge('project' => 'Optional')).fetch('project_id')).to eq('project')
    expect { client.discover(config.merge('project' => 'Missing')) }.to raise_error(Linear::Error, /Project/)
  end

  it 'rejects an unexpected workspace or guessed status' do
    expect { client.discover(config.merge('workspace' => 'wrong')) }.to raise_error(Linear::Error, /workspace/)
    expect { client.discover(config.merge('status' => 'Todo')) }.to raise_error(Linear::Error, /status/)
  end

  it 'follows team pagination before resolving exact names' do
    team_request = stub_request(:post, Linear::Client::ENDPOINT).with do |request|
      JSON.parse(request.body).fetch('query').include?('teams(')
    end
    team_request.to_return do |request|
      cursor = JSON.parse(request.body).fetch('variables')['after']
      page = if cursor
               { 'nodes' => [{ 'id' => 'team', 'name' => 'HC', 'key' => 'HC' }],
                 'pageInfo' => { 'hasNextPage' => false, 'endCursor' => nil } }
             else
               { 'nodes' => [], 'pageInfo' => { 'hasNextPage' => true, 'endCursor' => 'next' } }
             end
      { body: JSON.generate('data' => { 'teams' => page }) }
    end
    expect(client.discover(config).fetch('team_id')).to eq('team')
  end
end
