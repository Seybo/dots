# frozen_string_literal: true

require 'rspec'
require 'tempfile'
require_relative '../scripts/linear'

RSpec.describe LinearCli do
  let(:client) { instance_double(Linear::Client) }
  let(:registry) { instance_double(Linear::Registry) }
  let(:body) { "A **Markdown** reply.\n\nKeep the trailing newline.\n" }
  let(:comment) { { 'id' => 'comment-uuid', 'body' => body } }

  it 'posts a Markdown file as a comment without changing its contents' do
    Tempfile.create(['linear-comment-', '.md']) do |file|
      file.write(body)
      file.flush
      allow(client).to receive(:create_comment).with('HC-123', body).and_return(comment)

      expect { described_class.run(['comment-issue', 'HC-123', file.path], client: client, registry: registry) }
        .to output("#{JSON.pretty_generate(comment)}\n").to_stdout
      expect(client).to have_received(:create_comment).with('HC-123', body).once
    end
  end

  it 'reads a comment for verification' do
    allow(client).to receive(:get_comment).with('comment-uuid').and_return(comment)

    expect { described_class.run(%w[get-comment comment-uuid], client: client, registry: registry) }
      .to output("#{JSON.pretty_generate(comment)}\n").to_stdout
  end

  it 'prints the complete assigned issue listing' do
    listing = { 'issues' => [{ 'identifier' => 'HC-123' }], 'issues_count' => 1 }
    allow(client).to receive(:list_my_issues).and_return(listing)

    expect { described_class.run(['list-my-issues'], client: client, registry: registry) }
      .to output("#{JSON.pretty_generate(listing)}\n").to_stdout
  end

  it 'does not print partial listing output on API failure' do
    allow(client).to receive(:list_my_issues).and_raise(Linear::Error, 'Later page failed')

    expect do
      expect { described_class.run(['list-my-issues'], client: client, registry: registry) }
        .to raise_error(Linear::Error, /Later page failed/)
    end.to output('').to_stdout
  end

  it 'changes an explicitly requested multi-word status and prints the verified issue' do
    saved = { 'identifier' => 'HC-123', 'state' => { 'name' => 'Ready for Development' } }
    allow(client).to receive(:set_issue_status).with('HC-123', 'Ready for Development').and_return(saved)

    expect do
      described_class.run(['set-issue-status', 'HC-123', 'Ready for Development'], client: client, registry: registry)
    end.to output("#{JSON.pretty_generate(saved)}\n").to_stdout
  end

  it 'requires exactly one status argument before changing status' do
    expect do
      described_class.run(%w[set-issue-status HC-123], client: client, registry: registry)
    end.to raise_error(Linear::Error, /status name/)
    expect do
      described_class.run(%w[set-issue-status HC-123 In Progress], client: client, registry: registry)
    end.to raise_error(Linear::Error, /quote/)
  end

  it 'prints no success result when the status change cannot be verified' do
    allow(client).to receive(:set_issue_status).and_raise(Linear::Error, 'Status change could not be verified')

    expect do
      expect do
        described_class.run(%w[set-issue-status HC-123 Done], client: client, registry: registry)
      end.to raise_error(Linear::Error, /could not be verified/)
    end.to output('').to_stdout
  end

  it 'passes parent creation JSON unchanged to the shared client' do
    payload = { 'title' => 'Child', 'type' => 'Feature', 'parent' => 'HC-503' }
    config = { 'workspace' => 'shakacode' }
    allow(registry).to receive(:config).with('hc').and_return(config)
    allow(client).to receive(:discover).with(config).and_return({})
    allow(client).to receive(:create_issue).with(payload, {}).and_return('identifier' => 'HC-504')

    expect do
      described_class.run(['create-issue', 'hc', JSON.generate(payload)], client: client, registry: registry)
    end.to output(/HC-504/).to_stdout
  end

  it 'passes an optional parent and requester to draft conversion' do
    task = instance_double(Linear::Task)
    allow(Linear::Task).to receive(:new).with(client: client, registry: registry).and_return(task)
    allow(task).to receive(:convert).with('hc', '/draft/task.md', 'Feature',
                                          assignee_id: 'requester', parent: 'HC-503')
                                    .and_return('identifier' => 'HC-504')

    expect do
      described_class.run(%w[convert-draft hc /draft/task.md Feature --parent HC-503 requester],
                          client: client, registry: registry)
    end.to output(/HC-504/).to_stdout
  end

  it 'preserves conversion without a parent option' do
    task = instance_double(Linear::Task)
    allow(Linear::Task).to receive(:new).with(client: client, registry: registry).and_return(task)
    allow(task).to receive(:convert).with('hc', '/draft/task.md', 'Bug',
                                          assignee_id: nil, parent: nil).and_return('identifier' => 'HC-504')

    expect do
      described_class.run(%w[convert-draft hc /draft/task.md Bug], client: client, registry: registry)
    end.to output(/HC-504/).to_stdout
  end

  it 'rejects missing, repeated or unsupported conversion options before creation' do
    [%w[--parent], %w[--parent HC-503 --parent HC-502], %w[--unknown HC-503]].each do |options|
      expect do
        described_class.run(%w[convert-draft hc /draft/task.md Bug] + options, client: client, registry: registry)
      end.to raise_error(Linear::Error)
    end
  end

  it 'requires a source file before posting' do
    expect { described_class.run(%w[comment-issue HC-123], client: client, registry: registry) }
      .to raise_error(Linear::Error, /comment.md path/)
  end
end
