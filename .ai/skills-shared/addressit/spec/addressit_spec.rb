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
    it 'rejects an unsupported review agent' do
      expect { described_class.new(%w[--agent unknown]) }
        .to raise_error(Addressit::Error, /--agent must be one of: claude, codex/)
    end

    it 'derives resume context instead of storing it in state' do
      task_folder = File.join(@tmpdir, 'tasks', 'rails', '0001-fix-docs')
      code_repo = File.join(@tmpdir, 'code')
      files = Addressit::Files.new(task_folder)
      files.mkdirs
      FileUtils.mkdir_p(code_repo)
      system('git', '-C', code_repo, 'init', '-q')
      Addressit::Store.new(files.state_path).write(
        'review_agent' => 'codex',
        'phase' => 'awaiting_round_approval',
        'addressed_ids' => [],
        'skipped_ids' => [],
        'current_round' => 1
      )
      File.write(files.comments_path(1), JSON.generate([
        { 'id' => '1', 'html_url' => 'https://github.com/example/project/pull/123#discussion_r1' }
      ]))
      orchestrator = instance_double(Addressit::Orchestrator, approve!: nil)
      expect(Addressit::Orchestrator).to receive(:new) do |context, _files, _state|
        expect(context.project).to eq('rails')
        expect(context.task_id).to eq('0001')
        expect(context.repo_root).to eq(File.realpath(code_repo))
        expect(context.pr_repo).to eq('example/project')
        expect(context.pr_number).to eq('123')
        orchestrator
      end

      result = Addressit::CLI.new(['approve', task_folder, File.join(@tmpdir, 'approval.json')], cwd: code_repo).run

      expect(result).to eq(0)
    end

    it 'defaults to Codex, accepts an explicit Claude reviewer, and preserves legacy Claude runs' do
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
      state_path = File.join(task_folder, 'addressit-log/state.json')
      expect(Addressit::Store.new(state_path).read).to eq(
        'review_agent' => 'codex',
        'phase' => 'ready_to_fetch',
        'addressed_ids' => [],
        'skipped_ids' => []
      )

      expect(Addressit::CLI.new(%w[--clipboard --agent claude], cwd: code_repo).run).to eq(0)
      expect(Addressit::Store.new(state_path).read['review_agent']).to eq('claude')

      legacy_state = Addressit::Store.new(state_path).read
      legacy_state.delete('review_agent')
      legacy_state['version'] = 1
      legacy_state['project'] = 'rails'
      legacy_state['comment_ledger'] = [{ 'id' => '42', 'state' => 'addressed' }]
      Addressit::Store.new(state_path).write(legacy_state)
      expect(Addressit::CLI.new(['--clipboard'], cwd: code_repo).run).to eq(0)
      migrated_state = Addressit::Store.new(state_path).read
      expect(migrated_state['review_agent']).to eq('claude')
      expect(migrated_state['addressed_ids']).to eq(['42'])
      expect(migrated_state).not_to include('version', 'project', 'comment_ledger')

      waiting_state = Addressit::Store.new(state_path).read
      waiting_state['phase'] = 'waiting_for_reviewer'
      Addressit::Store.new(state_path).write(waiting_state)
      expect(Addressit::CLI.new(%w[--clipboard --agent codex], cwd: code_repo).run).to eq(1)
      expect(Addressit::Store.new(state_path).read['review_agent']).to eq('claude')
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
      expect(files.resolutions_path(2)).to end_with('rounds/round2_resolutions.json')
      expect(files.status_path(2, 'claude', 'review', 3)).to end_with('status/round2_claude_review3.json')
      expect(files.status_path(2, 'codex', 'review', 3)).to end_with('status/round2_codex_review3.json')
      expect(files.audit_path(2, 'pi')).to end_with('audits/round2_pi_blind_audit.md')
      expect(files.manager_hypotheses_path(2)).to end_with('audits/round2_manager_initial_review_hypotheses.json')
      expect(files.risk_manifest_path(2)).to end_with('audits/round2_risk_coverage_manifest.json')
      expect(files.manual_verification_path(2)).to end_with('audits/round2_manual_verification.json')
    end
  end

  describe Addressit::PromptWriter do
    it 'writes provider-neutral prompt names and Codex-specific status instructions' do
      files = Addressit::Files.new(File.join(@tmpdir, 'task'))
      files.mkdirs
      context = Addressit::Context.new(task_folder: files.task_folder, repo_root: File.join(@tmpdir, 'repo'))
      state = { 'current_round' => 2, 'review_agent' => 'codex' }

      path = described_class.new(files, context, state).reviewer_review(3, 'abc123')
      prompt = File.read(path)

      expect(path).to end_with('prompts/round2_reviewer_review3_request.md')
      expect(prompt).to include('Codex review agent')
      expect(prompt).to include('status/round2_codex_review3.json')
      expect(prompt).to include('"agent":"codex"')
    end
  end

  describe Addressit::FindingEvidence do
    let(:finding) do
      {
        'id' => 'F1',
        'severity' => 'BLOCKER',
        'title' => 'Reachable failure',
        'body' => 'The write fails.',
        'verification' => 'actionable',
        'trigger' => 'A production caller sends the input.',
        'mechanism' => 'The write happens before validation.',
        'reachability_source' => 'production_caller',
        'evidence' => 'app/services/import.rb:42 calls this branch.'
      }
    end

    it 'separates evidenced findings from findings that need operator verification' do
      findings = [
        finding,
        finding.merge('id' => 'F2', 'reachability_source' => 'unit_test_only'),
        finding.merge(
          'id' => 'F3',
          'verification' => 'needs_context',
          'missing_evidence' => 'Provider behavior is unknown.'
        )
      ]
      actionable, manual = described_class.partition(findings)

      expect(actionable.map { |item| item['id'] }).to eq(['F1'])
      expect(manual.map { |item| item['id'] }).to eq(%w[F2 F3])
      expect(manual.first['verification']).to eq('needs_context')
      expect(manual.first['missing_evidence']).to include('accepted reachability_source')
      expect(manual.last['missing_evidence']).to eq('Provider behavior is unknown.')
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
      context_class = Struct.new(:repo_root, :project, :task_id, :task_folder)
      context_class.new(repo_root, 'rails', '0001', task_folder)
    end

    it 'numbers from first-parent history and clears no-comment round state' do
      File.write(File.join(context.repo_root, 'tracked.txt'), "base\n")
      system('git', '-C', context.repo_root, 'config', 'user.email', 'addressit@example.test')
      system('git', '-C', context.repo_root, 'config', 'user.name', 'Addressit Spec')
      system('git', '-C', context.repo_root, 'add', 'tracked.txt')
      system('git', '-C', context.repo_root, 'commit', '-q', '-m', 'Add review updates 6')
      state = {
        'addressed_ids' => [],
        'skipped_ids' => [],
        'fix_iteration' => 8,
        'review_iteration' => 4,
        'debate_round' => 3
      }

      described_class.new(context, files, state).prepare_round!(double(comments: []))

      persisted = Addressit::Store.new(files.state_path).read
      expect(File.file?(files.comments_path(7))).to be(true)
      expect(persisted['phase']).to eq('no_new_comments')
      expect(persisted).not_to include('current_round', 'fix_iteration', 'review_iteration', 'debate_round')
    end

    it 'never selects addressed or skipped IDs again' do
      state = {
        'addressed_ids' => ['3663430805'],
        'skipped_ids' => ['3663430814']
      }
      comments = [
        { 'id' => '3663430805' },
        { 'id' => '3663430814' },
        { 'id' => '99' }
      ]

      orchestrator = described_class.new(context, files, state)
      orchestrator.instance_variable_set(:@repo, double(clean?: true, head_sha: 'head'))
      orchestrator.prepare_round!(double(comments: comments))

      selected = JSON.parse(File.read(files.comments_path(1)))
      expect(selected.map { |comment| comment['id'] }).to eq(['99'])
    end

    it 'stores skipped decisions only in skipped_ids' do
      state = {
        'phase' => 'awaiting_round_approval',
        'current_round' => 1,
        'addressed_ids' => [],
        'skipped_ids' => []
      }
      File.write(files.comments_path(1), JSON.generate([{ 'id' => '3663430805' }, { 'id' => '3663430814' }]))
      approval_path = File.join(@tmpdir, 'approval.json')
      approval = {
        'comments' => [
          { 'id' => '3663430805', 'decision' => 'skipped' },
          { 'id' => '3663430814', 'decision' => 'skipped' }
        ]
      }
      File.write(approval_path, JSON.generate(approval))

      described_class.new(context, files, state).approve!(approval_path)

      persisted = Addressit::Store.new(files.state_path).read
      expect(persisted['addressed_ids']).to eq([])
      expect(persisted['skipped_ids']).to eq(%w[3663430805 3663430814])
      expect(persisted).not_to include('comment_ledger', 'current_round', 'baseline_head', 'commit_shas')
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

    it 'pauses findings without reachability evidence before consuming a fix iteration' do
      state = {
        'phase' => 'ready_for_risk_reconciliation',
        'current_round' => 1,
        'review_iteration' => 1,
        'review_agent' => 'codex'
      }
      hypothesis = {
        'id' => 'H1',
        'kind' => 'contract',
        'check' => 'Check the provider contract.',
        'reason' => 'The integration crosses an external boundary.'
      }
      File.write(files.manager_hypotheses_path(1), JSON.generate('hypotheses' => [hypothesis]))
      File.write(files.status_path(1, 'pi', 'audit'), JSON.generate(
        'status' => 'done', 'agent' => 'pi', 'phase' => 'audit', 'step' => 0, 'summary' => 'No findings.', 'findings' => []
      ))
      File.write(files.status_path(1, 'codex', 'review', 1), JSON.generate(
        'status' => 'done', 'agent' => 'codex', 'phase' => 'review', 'step' => 0, 'summary' => 'No findings.', 'findings' => []
      ))
      manifest_path = File.join(@tmpdir, 'manifest.json')
      finding = {
        'id' => 'R1',
        'severity' => 'BLOCKER',
        'title' => 'Unknown provider behavior',
        'body' => 'The provider may reject the request.'
      }
      File.write(manifest_path, JSON.generate(
        'summary' => 'Reviewed.',
        'coverage_gaps' => [],
        'hypothesis_coverage' => [
          { 'id' => 'H1', 'status' => 'covered', 'note' => 'The provider behavior is not documented.' }
        ],
        'additional_findings' => [finding]
      ))

      described_class.new(context, files, state).reconcile_audit!(manifest_path)

      persisted = Addressit::Store.new(files.state_path).read
      verification = JSON.parse(File.read(files.manual_verification_path(1)))
      expect(persisted['phase']).to eq('awaiting_user')
      expect(persisted).not_to have_key('fix_iteration')
      expect(persisted['question']).to include('addressit resolve')
      expect(persisted).not_to include(
        'reviewer_findings', 'audit_findings', 'manual_verification_findings',
        'risk_manifest_path', 'risk_reconciliation_path'
      )
      expect(verification['manual_verification_ids']).to eq(['R1'])
    end

    it 'keeps review findings and resolutions in artifacts instead of state' do
      state = {
        'phase' => 'waiting_for_classify',
        'current_round' => 1,
        'review_iteration' => 1,
        'review_agent' => 'codex',
        'addressed_ids' => [],
        'skipped_ids' => []
      }
      finding = { 'id' => 'CODEX-F1', 'severity' => 'MINOR', 'title' => 'Finding', 'body' => 'Details.' }
      File.write(files.reconciliation_path(1), JSON.generate(
        'findings' => [finding],
        'manual_verification_findings' => []
      ))
      File.write(files.status_path(1, 'pi', 'classify', 1), JSON.generate(
        'status' => 'done',
        'agent' => 'pi',
        'phase' => 'classify',
        'step' => 0,
        'summary' => 'No fixes required.',
        'resolutions' => [{ 'finding_id' => 'CODEX-F1', 'decision' => 'follow_up', 'rationale' => 'Separate task.' }]
      ))

      described_class.new(context, files, state).run

      persisted = Addressit::Store.new(files.state_path).read
      resolutions = JSON.parse(File.read(files.resolutions_path(1)))
      expect(persisted['phase']).to eq('ready_for_manager_review')
      expect(persisted).not_to include('reviewer_findings', 'accepted_resolutions', 'final_checks')
      expect(resolutions['accepted_resolutions']).to eq([])
    end

    it 'uses the next unused first-parent number for the final squash commit' do
      state = {
        'phase' => 'ready_for_manager_review',
        'current_round' => 6,
        'addressed_ids' => [],
        'skipped_ids' => [],
        'commit_shas' => ['temporary'],
        'round_start_head' => 'base'
      }
      File.write(files.comments_path(6), JSON.generate([]))
      File.write(files.approval_path(6), JSON.generate('comments' => []))
      File.write(files.manager_review_path, "# Manager review\n")
      shell_result = double(success?: true, stdout: "Add review updates 6\n")
      shell = class_double(Autowork::Shell, capture: shell_result)
      repo = instance_double(Autowork::GitRepo)
      expect(repo).to receive(:squash_commits).with('base', 'Add review updates 7').and_return('squashed')
      orchestrator = described_class.new(context, files, state, shell: shell)
      orchestrator.instance_variable_set(:@repo, repo)

      orchestrator.manager_pass!

      persisted = Addressit::Store.new(files.state_path).read
      expect(persisted['phase']).to eq('complete')
      expect(persisted).not_to include('current_round', 'commit_shas', 'round_start_head')
    end

    it 'applies registry updates only after squashing the round commits' do
      state = {
        'phase' => 'ready_for_manager_review',
        'current_round' => 1,
        'review_agent' => 'codex',
        'addressed_ids' => [],
        'skipped_ids' => [],
        'commit_shas' => ['implementation'],
        'round_start_head' => 'base'
      }
      File.write(files.comments_path(1), JSON.generate([{ 'id' => 1 }]))
      File.write(files.approval_path(1), JSON.generate('comments' => [{ 'id' => '1', 'decision' => 'approved' }]))
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
      expect(Addressit::Store.new(files.state_path).read).to eq(
        'phase' => 'complete',
        'review_agent' => 'codex',
        'addressed_ids' => ['1'],
        'skipped_ids' => []
      )
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
      expect(comments).to all(satisfy { |comment| !comment.key?('updated_at') })
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

  describe Addressit::Lock do
    it 'releases a killed owner lock for the next Addressit process' do
      path = File.join(@tmpdir, 'addressit-log', 'run.lock')
      reader, writer = IO.pipe
      child_pid = fork do
        reader.close
        described_class.new(path).acquire!
        writer.write('locked')
        writer.close
        sleep 60
      end
      writer.close
      expect(reader.read).to eq('locked')

      expect { described_class.new(path).acquire! }
        .to raise_error(Addressit::Error, /Addressit is already running/)

      Process.kill('KILL', child_pid)
      Process.wait(child_pid)

      recovered_lock = described_class.new(path)
      expect { recovered_lock.acquire! }.not_to raise_error
      recovered_lock.release
    ensure
      reader&.close unless reader&.closed?
      writer&.close unless writer&.closed?
      begin
        Process.kill('KILL', child_pid) if child_pid
      rescue Errno::ESRCH
        nil
      end
      begin
        Process.wait(child_pid) if child_pid
      rescue Errno::ECHILD
        nil
      end
    end
  end
end
