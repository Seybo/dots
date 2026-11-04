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

  it 'requires a source file before posting' do
    expect { described_class.run(%w[comment-issue HC-123], client: client, registry: registry) }
      .to raise_error(Linear::Error, /comment.md path/)
  end
end
