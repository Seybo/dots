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

  describe Addressit::CLI do
    it 'saves task repo changes before starting a new run' do
      task_repo = File.join(@tmpdir, 'tasks', 'rails')
      task_folder = File.join(task_repo, '0001-fix-docs')
      code_repo = File.join(@tmpdir, 'code')
      FileUtils.mkdir_p(task_folder)
      FileUtils.mkdir_p(code_repo)
      [task_repo, code_repo].each do |repo|
        system('git', '-C', repo, 'init', '-q')
        system('git', '-C', repo, 'config', 'user.email', 'addressit@example.test')
        system('git', '-C', repo, 'config', 'user.name', 'Addressit Spec')
      end
      File.write(File.join(task_folder, 'task.md'), "# Task\n")
      FileUtils.mkdir_p(File.join(task_folder, 'autowork-log'))
      File.write(File.join(task_folder, 'autowork-log', 'state.json'), JSON.generate('status' => 'done', 'phase' => 'complete'))

      context = Addressit::Context.new(
        project: 'rails',
        task_id: '0001',
        task_folder: task_folder,
        repo_root: code_repo,
        branch: 'master',
      )
      resolver = instance_double(Addressit::TaskResolver, resolve: context)
      orchestrator = instance_double(Addressit::Orchestrator)
      allow(Addressit::TaskResolver).to receive(:new).and_return(resolver)
      allow(Addressit::Orchestrator).to receive(:new).and_return(orchestrator)
      allow(orchestrator).to receive(:prepare_round!)

      expect(Addressit::CLI.new(['--clipboard'], cwd: code_repo).run).to eq(0)
      expect(`git -C #{task_repo} log -1 --format=%s`.strip).to eq('save')
      expect(`git -C #{task_repo} show HEAD:0001-fix-docs/task.md`).to eq("# Task\n")
      expect(`git -C #{task_repo} status --porcelain`.strip).to include('?? 0001-fix-docs/addressit-log/')
    end
  end

  describe Addressit::Files do
    it 'creates the addressit-log layout and exposes round paths' do
      files = described_class.new(File.join(@tmpdir, 'task'))
      files.mkdirs

      expect(File.directory?(files.log_dir)).to be(true)
      expect(files.comments_path(2)).to end_with('rounds/round2_comments.json')
      expect(files.status_path(2, 'claude', 'review', 3)).to end_with('status/round2_claude_review3.json')
      expect(files.audit_path(2, 'pi')).to end_with('audits/round2_pi_blind_audit.md')
      expect(files.manager_hypotheses_path(2)).to end_with('audits/round2_manager_initial_review_hypotheses.json')
      expect(files.risk_manifest_path(2)).to end_with('audits/round2_risk_coverage_manifest.json')
    end
  end

  describe Addressit::Orchestrator do
    let(:task_folder) { File.join(@tmpdir, 'task') }
    let(:files) do
      instance = Addressit::Files.new(task_folder)
      instance.mkdirs
      instance
    end
    let(:context) do
      repo_root = File.join(@tmpdir, 'repo')
      FileUtils.mkdir_p(repo_root)
      system('git', '-C', repo_root, 'init', '-q')
      Struct.new(:repo_root, :project, :task_id).new(repo_root, 'rails', '0001')
    end

    it 'rejects empty manager hypotheses before starting the blind audit' do
      state = { 'phase' => 'ready_for_manager_hypotheses', 'current_round' => 1 }
      orchestrator = described_class.new(context, files, state)
      hypotheses_path = File.join(@tmpdir, 'hypotheses.json')
      File.write(hypotheses_path, JSON.generate('hypotheses' => []))

      expect { orchestrator.start_audit!(hypotheses_path) }
        .to raise_error(Addressit::Error, /non-empty array/)
    end

    it 'requires reconciliation to acknowledge every manager hypothesis' do
      state = {
        'phase' => 'ready_for_risk_reconciliation',
        'current_round' => 1,
        'manager_hypotheses_path' => files.manager_hypotheses_path(1)
      }
      File.write(files.manager_hypotheses_path(1), JSON.generate(
        'hypotheses' => [{ 'id' => 'H1', 'kind' => 'contract', 'check' => 'Check the provider contract.', 'reason' => 'The integration crosses an external boundary.' }]
      ))
      orchestrator = described_class.new(context, files, state)
      manifest_path = File.join(@tmpdir, 'manifest.json')
      File.write(manifest_path, JSON.generate('summary' => 'Reviewed.', 'coverage_gaps' => []))

      expect { orchestrator.reconcile_audit!(manifest_path) }
        .to raise_error(Addressit::Error, /hypothesis_coverage must be a present array/)
    end

    it 'applies registry updates only after squashing the round commits' do
      state = {
        'phase' => 'ready_for_manager_review',
        'current_round' => 1,
        'commits' => ['implementation'],
        'comment_ledger' => [],
        'rounds' => [{ 'number' => 1, 'risk_audit_required' => true, 'approved_ids' => ['1'], 'commit_shas' => ['implementation'], 'round_start_head' => 'base' }]
      }
      File.write(files.comments_path(1), JSON.generate([{ 'id' => 1 }]))
      File.write(files.manager_review_path, '# Manager review\n')
      File.write(files.risk_manifest_path(1), JSON.generate(
        'summary' => 'Reviewed.',
        'coverage_gaps' => [],
        'registry_updates' => [{ 'id' => 'risk-1', 'summary' => 'Protect the write.' }]
      ))
      File.write(files.reconciliation_path(1), "# Reconciliation\n")
      orchestrator = described_class.new(context, files, state)
      calls = []
      repo = instance_double(Autowork::GitRepo)
      allow(repo).to receive(:squash_commits) do
        calls << :squash
        'squashed'
      end
      orchestrator.instance_variable_set(:@repo, repo)
      registry = instance_double(Autowork::ReviewRiskRegistry)
      allow(registry).to receive(:apply!) { calls << :registry }
      allow(Autowork::ReviewRiskRegistry).to receive(:new).with('rails').and_return(registry)

      orchestrator.manager_pass!

      expect(calls).to eq(%i[squash registry])
    end
  end

  describe Addressit::ClipboardReview do
    it 'imports the clipboard as one stable local review item' do
      shell = double(capture!: "P1 — reserve before provider write\n")

      comments = described_class.new(shell: shell).comments

      expect(comments.length).to eq(1)
      expect(comments.first['id']).to start_with('local-')
      expect(comments.first['kind']).to eq('local_review')
      expect(comments.first['body']).to include('reserve before provider write')
      expect(comments.first['user']['login']).to eq('local-review')
    end
  end

  describe Addressit::TaskResolver do
    it 'resolves a direct checkout with an explicit local task id' do
      repo_root = File.join(@tmpdir, 'rails')
      task_root = File.join(@tmpdir, 'tasks')
      task_folder = File.join(task_root, 'rails', '0001-fix-docs')
      registry = File.join(@tmpdir, 'projects.yml')
      FileUtils.mkdir_p(repo_root)
      FileUtils.mkdir_p(task_folder)
      File.write(File.join(task_folder, 'task.md'), '# Task\n')
      File.write(registry, <<~YAML)
        projects:
          rails:
            checkout_layout: direct
            checkout_path: #{File.realpath(repo_root)}
            task_provider: local
      YAML

      shell = class_double(Autowork::Shell)
      allow(shell).to receive(:capture!).with('git', '-C', anything, 'rev-parse', '--show-toplevel').and_return(repo_root)
      allow(shell).to receive(:capture!).with('git', '-C', File.realpath(repo_root), 'branch', '--show-current').and_return('fix-docs')

      stub_const('Addressit::TASK_ROOT', task_root)
      context = described_class.new(cwd: repo_root, shell: shell, projects_file: registry).resolve(task_id: '0001')

      expect(context.project).to eq('rails')
      expect(context.task_folder).to eq(task_folder)
      expect(context.branch).to eq('fix-docs')
    end

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
        return JSON.generate({ 'number' => 123, 'url' => 'https://github.com/example/project/pull/123' }) if args == ['gh', 'pr', 'view', '--json', 'number,url']
        return JSON.generate(@payload) if args.first(2) == ['gh', 'api']

        raise "unexpected command: #{args.inspect}"
      end
    end

    it 'discovers the current pull request when no target is provided' do
      github = described_class.new([], shell: shell = FakeShell.new([]))

      expect(github.repo).to eq('example/project')
      expect(github.number).to eq('123')
      expect(shell.calls).to include(['gh', 'pr', 'view', '--json', 'number,url'])
    end

    it 'supports standalone since filters with implicit PR discovery' do
      shell = FakeShell.new([
        { 'id' => 1, 'user' => { 'login' => 'alice' }, 'created_at' => '2026-07-22T12:00:00Z', 'updated_at' => '2026-07-22T12:00:00Z' },
        { 'id' => 2, 'user' => { 'login' => 'bob' }, 'created_at' => '2020-01-01T12:00:00Z', 'updated_at' => '2020-01-01T12:00:00Z' }
      ])

      comments = described_class.new(%w[since 2020-01-01T00:00:00Z], shell: shell).comments

      expect(comments.map { |comment| comment['id'] }).to eq([2, 1])
    end

    it 'supports standalone since filters with an explicit PR target' do
      shell = FakeShell.new([
        { 'id' => 1, 'user' => { 'login' => 'alice' }, 'created_at' => '2026-07-22T12:00:00Z', 'updated_at' => '2026-07-22T12:00:00Z' },
        { 'id' => 2, 'user' => { 'login' => 'bob' }, 'created_at' => '2020-01-01T12:00:00Z', 'updated_at' => '2020-01-01T12:00:00Z' }
      ])

      comments = described_class.new(%w[123 since 2020-01-01T00:00:00Z], shell: shell).comments

      expect(comments.map { |comment| comment['id'] }).to eq([2, 1])
    end

    it 'keeps bare comments as a no-op filter' do
      shell = FakeShell.new([
        { 'id' => 1, 'user' => { 'login' => 'alice' }, 'created_at' => '2026-07-22T12:00:00Z', 'updated_at' => '2026-07-22T12:00:00Z' },
        { 'id' => 2, 'user' => { 'login' => 'bob' }, 'created_at' => '2026-07-22T12:01:00Z', 'updated_at' => '2026-07-22T12:01:00Z' }
      ])

      comments = described_class.new(%w[comments], shell: shell).comments

      expect(comments.map { |comment| comment['id'] }).to eq([1, 2])
    end

    it 'fetches all comment kinds for all-comments filters' do
      shell = FakeShell.new([])

      described_class.new(['all', 'comments'], shell: shell).comments

      expect(shell.calls).to include(
        ['gh', 'api', 'repos/example/project/pulls/123/comments', '--paginate'],
        ['gh', 'api', 'repos/example/project/pulls/123/reviews', '--paginate'],
        ['gh', 'api', 'repos/example/project/issues/123/comments', '--paginate']
      )
    end

    it 'supports all-comments filters combined with a reviewer' do
      shell = FakeShell.new([])

      described_class.new(%w[123 all comments from alice], shell: shell).comments

      expect(shell.calls.count { |call| call[0, 2] == ['gh', 'api'] }).to eq(3)
    end

    it 'rejects invalid since values before fetching comments' do
      shell = FakeShell.new([])

      expect { described_class.new(%w[123 since nonsense], shell: shell) }
        .to raise_error(Addressit::Error, /Could not parse since filter/)
      expect(shell.calls.none? { |call| call.first(2) == ['gh', 'api'] }).to be(true)
    end

    it 'rejects malformed ISO since values before fetching comments' do
      shell = FakeShell.new([])

      expect { described_class.new(%w[123 since 2026-99-99T00:00:00Z], shell: shell) }
        .to raise_error(Addressit::Error, /Could not parse since filter/)
      expect(shell.calls.none? { |call| call.first(2) == ['gh', 'api'] }).to be(true)
    end

    it 'rejects invalid filters before fetching comments' do
      shell = FakeShell.new([])

      expect { described_class.new(%w[123 comments typo], shell: shell) }
        .to raise_error(Addressit::Error, /Invalid comment filter/)
      expect(shell.calls.none? { |call| call.first(2) == ['gh', 'api'] }).to be(true)
    end

    it 'rejects an invalid target instead of treating it as a filter' do
      expect { described_class.new(['123abc'], shell: FakeShell.new([])) }
        .to raise_error(Addressit::Error, /Invalid PR target/)
    end

    it 'uses explicit pull request URL fragments to select a comment' do
      shell = FakeShell.new([
        { 'id' => 456, 'user' => { 'login' => 'alice' }, 'created_at' => '2026-07-22T12:00:00Z', 'updated_at' => '2026-07-22T12:00:00Z' },
        { 'id' => 789, 'user' => { 'login' => 'bob' }, 'created_at' => '2026-07-22T12:01:00Z', 'updated_at' => '2026-07-22T12:01:00Z' }
      ])
      github = described_class.new(['https://github.com/example/project/pull/123#discussion_r456'], shell: shell)

      expect(github.comments.map { |comment| comment['id'] }).to eq([456])
    end

    it 'discovers the current pull request before applying filters' do
      shell = FakeShell.new([
        { 'id' => 1, 'user' => { 'login' => 'alice' }, 'created_at' => '2026-07-22T12:00:00Z', 'updated_at' => '2026-07-22T12:00:00Z' },
        { 'id' => 2, 'user' => { 'login' => 'bob' }, 'created_at' => '2026-07-22T12:01:00Z', 'updated_at' => '2026-07-22T12:01:00Z' }
      ])

      comments = described_class.new(%w[comments from alice], shell: shell).comments

      expect(comments.map { |comment| comment['id'] }).to eq([1])
      expect(shell.calls).to include(['gh', 'pr', 'view', '--json', 'number,url'])
    end

    it 'rejects malformed current pull request data' do
      shell = Class.new(FakeShell) do
        def initialize
          super([])
        end

        def capture!(*args)
          return '[]' if args == ['gh', 'pr', 'view', '--json', 'number,url']

          super
        end
      end.new

      expect { described_class.new([], shell: shell) }
        .to raise_error(Addressit::Error, /valid pull request/)
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
