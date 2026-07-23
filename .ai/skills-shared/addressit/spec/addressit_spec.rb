# frozen_string_literal: true

require 'json'
require 'tmpdir'
require 'fileutils'
require 'rspec'

require_relative '../lib/addressit'

RSpec.describe Addressit do
  around do |example|
    Dir.mktmpdir('addressit-spec') do |dir|
      @tmpdir = dir
      example.run
    end
  end

  describe Addressit::Files do
    it 'creates the addressit-log layout and exposes round paths' do
      files = described_class.new(File.join(@tmpdir, 'task'))
      files.mkdirs

      expect(File.directory?(files.log_dir)).to be(true)
      expect(files.comments_path(2)).to end_with('rounds/round2_comments.json')
      expect(files.status_path(2, 'claude', 'review', 3)).to end_with('status/round2_claude_review3.json')
    end
  end

  describe Addressit::TaskResolver do
    it 'resolves projects and arbitrary workspaces from the shared registry' do
      code_root = File.join(@tmpdir, 'projects', 'shaka', 'trp')
      FileUtils.mkdir_p(code_root)
      code_root = File.realpath(code_root)
      repo_root = File.join(code_root, '28th')
      task_root = File.join(@tmpdir, 'tasks')
      task_folder = File.join(task_root, 'shaka_trp', '1234-task')
      registry = File.join(@tmpdir, 'projects.yml')
      FileUtils.mkdir_p(repo_root)
      FileUtils.mkdir_p(task_folder)
      File.write(File.join(task_folder, 'task.md'), '# Task\n')
      File.write(registry, <<~YAML)
        projects:
          shaka_trp:
            code_root: #{code_root}
            tmux_layout: agent
            agent_command: pi-w
      YAML

      shell = class_double(Autowork::Shell)
      allow(shell).to receive(:capture!).with('git', '-C', anything, 'rev-parse', '--show-toplevel').and_return(repo_root)
      allow(shell).to receive(:capture!).with('git', '-C', repo_root, 'branch', '--show-current').and_return('sc-1234/fix')

      stub_const('Addressit::TASK_ROOT', task_root)
      context = described_class.new(cwd: repo_root, shell: shell, projects_file: registry).resolve

      expect(context.project).to eq('shaka_trp')
      expect(context.task_folder).to eq(task_folder)
      expect(context.repo_root).to eq(repo_root)
    end
  end

  describe Addressit::Ledger do
    let(:state) { { 'comment_ledger' => [] } }
    let(:comment) { { 'id' => 42, 'updated_at' => '2026-07-22T12:00:00Z' } }

    it 'only filters an addressed comment at the same version' do
      ledger = described_class.new(state)
      ledger.save(comment, state: 'addressed')

      expect(ledger.addressed_or_skipped?(comment)).to be(true)
      expect(ledger.addressed_or_skipped?(comment.merge('updated_at' => '2026-07-22T13:00:00Z'))).to be(false)
    end

    it 'keeps skipped separate from addressed' do
      ledger = described_class.new(state)
      ledger.save(comment, state: 'skipped')

      expect(state['comment_ledger'].first['state']).to eq('skipped')
      expect(ledger.addressed_or_skipped?(comment)).to be(true)
    end
  end

  describe Addressit::GitHub do
    FakeResult = Struct.new(:stdout, :stderr, :status) do
      def success? = status == 0
    end

    class FakeShell
      attr_reader :calls

      def initialize(payload)
        @payload = payload
        @calls = []
      end

      def capture!(*args)
        @calls << args
        return 'example/project' if args == ['gh', 'repo', 'view', '--json', 'nameWithOwner', '-q', '.nameWithOwner']
        return JSON.generate(@payload) if args.first(2) == ['gh', 'api']

        raise "unexpected command: #{args.inspect}"
      end
    end

    it 'fetches and filters inline comments by reviewer' do
      shell = FakeShell.new([
        { 'id' => 1, 'user' => { 'login' => 'alice' }, 'created_at' => '2026-07-22T12:00:00Z', 'updated_at' => '2026-07-22T12:00:00Z' },
        { 'id' => 2, 'user' => { 'login' => 'bob' }, 'created_at' => '2026-07-22T12:01:00Z', 'updated_at' => '2026-07-22T12:01:00Z' }
      ])

      comments = described_class.new(%w[123 comments from alice], shell: shell).comments

      expect(comments.map { |comment| comment['id'] }).to eq([1])
      expect(shell.calls).to include(['gh', 'api', 'repos/example/project/pulls/123/comments', '--paginate'])
    end
  end
end
