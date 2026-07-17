# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'
require 'json'
require 'rspec'
require 'stringio'
require 'yaml'

require_relative '../lib/autowork'

RSpec.describe Autowork do
  around do |example|
    Dir.mktmpdir('autowork-spec') do |dir|
      @tmpdir = dir
      example.run
    end
  end

  def make_env_task(task_id: '0003')
    task_root = File.join(@tmpdir, '_tasks')
    task_folder = File.join(task_root, 'env', "#{task_id}-test-task")
    FileUtils.mkdir_p(task_folder)
    File.write(File.join(task_folder, 'task.md'), "# Task\n")
    File.write(File.join(task_folder, 'steps.md'), <<~MD)
      # Plan

      ## Step 1: First slice
      Do one thing.
    MD
    [task_root, task_folder]
  end

  def make_git_repo
    repo = File.join(@tmpdir, 'dots')
    FileUtils.mkdir_p(repo)
    system('git', '-C', repo, 'init', out: File::NULL, err: File::NULL)
    system('git', '-C', repo, 'config', 'user.email', 'autowork@example.test', out: File::NULL, err: File::NULL)
    system('git', '-C', repo, 'config', 'user.name', 'Autowork Spec', out: File::NULL, err: File::NULL)
    repo
  end

  def pane(id:, title:, path:)
    Autowork::Pane.new(
      id: id,
      session: 'work',
      window_id: '@1',
      window_name: 'agents',
      active: title == 'pi-manager',
      command: 'zsh',
      title: title,
      path: path
    )
  end

  def role_panes(repo)
    Autowork::RolePanes.new(
      manager: pane(id: '%1', title: 'pi-manager', path: repo),
      pi_worker: pane(id: '%2', title: 'pi-worker', path: repo),
      claude_worker: pane(id: '%3', title: 'claude-worker', path: repo)
    )
  end

  describe Autowork::Steps do
    it 'parses step numbers from canonical headings' do
      path = File.join(@tmpdir, 'steps.md')
      File.write(path, <<~MD)
        # Plan

        ## Step 1: First slice
        Do one thing.

        ## Step 2: Second slice
        Do another thing.
      MD

      steps = described_class.new(path)

      expect(steps.numbers).to eq([1, 2])
      expect(steps.count).to eq(2)
    end

    it 'rejects missing steps files' do
      path = File.join(@tmpdir, 'missing.md')

      expect { described_class.new(path) }
        .to raise_error(Autowork::Error, /Missing required steps file/)
    end

    it 'rejects steps files without parseable step headings' do
      path = File.join(@tmpdir, 'steps.md')
      File.write(path, "# Plan\n\n### Slice one\n")

      expect { described_class.new(path) }
        .to raise_error(Autowork::Error, /has no headings matching/)
    end
  end

  describe Autowork::TaskResolver do
    it 'resolves an explicit env task folder by prefix' do
      task_root, task_folder = make_env_task(task_id: '1234')
      dots_repo = make_git_repo

      stub_const('Autowork::TASK_ROOT', task_root)
      stub_const('Autowork::DOTS_REPO', dots_repo)

      context = described_class.new(%w[env 1234], cwd: dots_repo).resolve

      expect(context.project).to eq('env')
      expect(context.task_id).to eq('1234')
      expect(context.task_root).to eq(File.join(task_root, 'env'))
      expect(context.task_folder).to eq(task_folder)
      expect(context.code_dir).to eq(dots_repo)
    end

    it 'infers env project from cwd when passed only a task id' do
      task_root, task_folder = make_env_task
      dots_repo = make_git_repo
      cwd = File.join(dots_repo, 'subdir')
      FileUtils.mkdir_p(cwd)

      stub_const('Autowork::TASK_ROOT', task_root)
      stub_const('Autowork::DOTS_REPO', dots_repo)

      context = described_class.new(['0003'], cwd: cwd).resolve

      expect(context.project).to eq('env')
      expect(context.task_id).to eq('0003')
      expect(context.task_folder).to eq(task_folder)
      expect(context.code_dir).to eq(dots_repo)
    end

    it 'normalizes GTM aliases to the shared task project and selected checkout' do
      task_root = File.join(@tmpdir, '_tasks')
      FileUtils.mkdir_p(File.join(task_root, 'shaka_gtm', '12345-test-task'))

      stub_const('Autowork::TASK_ROOT', task_root)

      context = described_class.new(%w[shaka_gtm1 12345], cwd: @tmpdir).resolve

      expect(context.project).to eq('shaka_gtm')
      expect(context.task_root).to eq(File.join(task_root, 'shaka_gtm'))
      expect(context.task_folder).to eq(File.join(task_root, 'shaka_gtm', '12345-test-task'))
      expect(context.code_dir).to eq('/Volumes/dev/projects/shaka/gtm/1st')
    end

    it 'fails when a task id prefix is ambiguous' do
      task_root = File.join(@tmpdir, '_tasks')
      dots_repo = make_git_repo
      FileUtils.mkdir_p(File.join(task_root, 'env', '0003-alpha'))
      FileUtils.mkdir_p(File.join(task_root, 'env', '0003-beta'))

      stub_const('Autowork::TASK_ROOT', task_root)
      stub_const('Autowork::DOTS_REPO', dots_repo)

      expect { described_class.new(%w[env 0003], cwd: dots_repo).resolve }
        .to raise_error(Autowork::Error, /Multiple task folders match/)
    end

    it 'requires task ids to be digits only' do
      task_root, = make_env_task
      dots_repo = make_git_repo

      stub_const('Autowork::TASK_ROOT', task_root)
      stub_const('Autowork::DOTS_REPO', dots_repo)

      expect { described_class.new(%w[env abc], cwd: dots_repo).resolve }
        .to raise_error(Autowork::Error, /digits only/)
    end
  end

  describe Autowork::StatusValidator do
    let(:validator) { described_class.new }

    it 'accepts a valid done status' do
      result = validator.validate_hash(
        {
          'status' => 'done',
          'agent' => 'pi',
          'phase' => 'implement',
          'step' => 1,
          'summary' => 'implemented step',
          'checks_run' => []
        }
      )

      expect(result).to be_valid
    end

    it 'rejects missing required fields' do
      result = validator.validate_hash({ 'status' => 'done' })

      expect(result).not_to be_valid
      expect(result.errors).to include('agent is required', 'phase is required', 'summary is required', 'step is required')
    end

    it 'requires a question for needs_user statuses' do
      result = validator.validate_hash(
        {
          'status' => 'needs_user',
          'agent' => 'claude',
          'phase' => 'review',
          'step' => 1,
          'summary' => 'need product decision'
        }
      )

      expect(result).not_to be_valid
      expect(result.errors).to include('question is required when status is needs_user')
    end

    it 'checks expected agent, phase, and step' do
      result = validator.validate_hash(
        {
          'status' => 'done',
          'agent' => 'pi',
          'phase' => 'implement',
          'step' => 1,
          'summary' => 'done'
        },
        expected: { agent: 'claude', phase: 'review', step: 2 }
      )

      expect(result).not_to be_valid
      expect(result.errors).to include('agent expected "claude", got "pi"')
      expect(result.errors).to include('phase expected "review", got "implement"')
      expect(result.errors).to include('step expected 2, got 1')
    end

    it 'reports invalid JSON status files' do
      path = File.join(@tmpdir, 'status.json')
      File.write(path, '{ nope')

      result = validator.validate_file(path)

      expect(result).not_to be_valid
      expect(result.errors.join).to include('invalid JSON')
    end
  end

  describe Autowork::RunFiles do
    it 'creates the expected autowork-log subdirectories' do
      task_folder = File.join(@tmpdir, 'task')
      files = described_class.new(task_folder)

      files.mkdirs

      expect(File.directory?(files.log_dir)).to be(true)
      %w[control prompts reviews debates resolutions status].each do |name|
        expect(File.directory?(File.join(files.log_dir, name))).to be(true)
      end
      expect(files.config_path).to eq(File.join(files.log_dir, 'config.yml'))
      expect(files.state_path).to eq(File.join(files.log_dir, 'state.json'))
      expect(files.prompt_path('step1_pi_implement_request.md')).to eq(File.join(files.log_dir, 'prompts', 'step1_pi_implement_request.md'))
    end
  end

  describe Autowork::StateStore do
    it 'writes and reads JSON state' do
      path = File.join(@tmpdir, 'autowork-log', 'state.json')
      store = described_class.new(path)
      state = { 'status' => 'initialized', 'current_step' => 1 }

      store.write(state)

      expect(store.read).to eq(state)
    end

    it 'rejects missing state files' do
      store = described_class.new(File.join(@tmpdir, 'missing.json'))

      expect { store.read }.to raise_error(Autowork::Error, /Missing state file/)
    end
  end

  describe Autowork::RunLock do
    it 'creates and releases a lock file' do
      lock = described_class.new(File.join(@tmpdir, 'autowork-log', 'run.lock'))

      expect(lock.acquire!).to be(true)
      expect(lock.lock_pid).to eq(Process.pid)

      lock.release!
      expect(File.file?(lock.path)).to be(false)
    end

    it 'rejects a lock held by a live pid' do
      path = File.join(@tmpdir, 'run.lock')
      File.write(path, JSON.pretty_generate('pid' => Process.pid))
      lock = described_class.new(path)

      expect { lock.acquire! }.to raise_error(Autowork::Error, /already locked/)
    end

    it 'replaces a stale lock' do
      path = File.join(@tmpdir, 'run.lock')
      File.write(path, JSON.pretty_generate('pid' => 999_999_999))
      lock = described_class.new(path)

      expect(lock.acquire!).to be(true)
      expect(lock.lock_pid).to eq(Process.pid)
    end
  end

  describe Autowork::Tmux do
    it 'discovers required panes by exact title in the current window and validates their git root' do
      tmux = described_class.new
      repo_root = make_git_repo
      panes = [
        pane(id: '%1', title: 'pi-manager', path: repo_root),
        pane(id: '%2', title: 'pi-worker', path: repo_root),
        pane(id: '%3', title: 'claude-worker', path: repo_root)
      ]

      allow(tmux).to receive(:panes).and_return(panes)

      roles = tmux.discover_roles(repo_root)

      expect(roles.manager.title).to eq('pi-manager')
      expect(roles.pi_worker.title).to eq('pi-worker')
      expect(roles.claude_worker.title).to eq('claude-worker')
    end

    it 'rejects missing exact pane titles' do
      tmux = described_class.new
      repo_root = make_git_repo
      panes = [
        pane(id: '%1', title: 'pi-manager', path: repo_root),
        pane(id: '%2', title: 'pi-worker', path: repo_root)
      ]

      allow(tmux).to receive(:panes).and_return(panes)

      expect { tmux.discover_roles(repo_root) }
        .to raise_error(Autowork::Error, /No tmux pane titled "claude-worker"/)
    end

    it 'rejects duplicate exact pane titles' do
      tmux = described_class.new
      repo_root = make_git_repo
      panes = [
        pane(id: '%1', title: 'pi-manager', path: repo_root),
        pane(id: '%2', title: 'pi-worker', path: repo_root),
        pane(id: '%3', title: 'claude-worker', path: repo_root),
        pane(id: '%4', title: 'claude-worker', path: repo_root)
      ]

      allow(tmux).to receive(:panes).and_return(panes)

      expect { tmux.discover_roles(repo_root) }
        .to raise_error(Autowork::Error, /Multiple tmux panes titled "claude-worker"/)
    end
  end

  describe Autowork::Initializer do
    it 'refuses to initialize when the repo is dirty' do
      task_root, = make_env_task
      repo = make_git_repo
      File.write(File.join(repo, 'dirty.txt'), 'dirty')

      stub_const('Autowork::TASK_ROOT', task_root)
      stub_const('Autowork::DOTS_REPO', repo)

      expect { described_class.new(%w[env 0003]).run }
        .to raise_error(Autowork::Error, /Refusing to start with dirty worktree/)
    end

    it 'creates config, state, and the first pi-worker prompt for a clean run' do
      task_root, task_folder = make_env_task
      repo = make_git_repo
      tmux = instance_double(Autowork::Tmux, discover_roles: role_panes(repo))

      stub_const('Autowork::TASK_ROOT', task_root)
      stub_const('Autowork::DOTS_REPO', repo)
      allow(Autowork::Tmux).to receive(:new).and_return(tmux)

      described_class.new(%w[env 0003]).run

      files = Autowork::RunFiles.new(task_folder)
      config = YAML.safe_load(File.read(files.config_path))
      state = JSON.parse(File.read(files.state_path))
      prompt = File.read(files.prompt_path('step1_pi_implement_request.md'))

      expect(config['pi_manager_target']).to eq('%1')
      expect(config['pi_worker_target']).to eq('%2')
      expect(config['claude_worker_target']).to eq('%3')
      expect(state['status']).to eq('initialized')
      expect(state['current_step']).to eq(1)
      expect(prompt).to include('as `pi-worker`')
      expect(prompt).to include('Implement only `## Step 1`')
    end
  end

  describe Autowork::Orchestrator do
    around do |example|
      previous = ENV['AUTOWORK_WORKER_STATUS_TIMEOUT_SECONDS']
      ENV['AUTOWORK_WORKER_STATUS_TIMEOUT_SECONDS'] = '0'
      example.run
    ensure
      ENV['AUTOWORK_WORKER_STATUS_TIMEOUT_SECONDS'] = previous
    end

    it 'initializes, sends the pi-worker prompt, and records the waiting phase' do
      task_root, task_folder = make_env_task
      repo = make_git_repo
      tmux = instance_double(Autowork::Tmux, discover_roles: role_panes(repo))
      allow(tmux).to receive(:send_prompt)

      stub_const('Autowork::TASK_ROOT', task_root)
      stub_const('Autowork::DOTS_REPO', repo)

      expect { described_class.new(%w[env 0003], tmux: tmux).run }
        .to raise_error(Autowork::Error, /Worker status timeout/)

      files = Autowork::RunFiles.new(task_folder)
      state = JSON.parse(File.read(files.state_path))
      expect(tmux).to have_received(:send_prompt).with('%2', files.prompt_path('step1_pi_implement_request.md'))
      expect(state['status']).to eq('running')
      expect(state['phase']).to eq('waiting_for_pi_implement')
    end

    it 'keeps waiting when a status file is temporarily invalid while being written' do
      previous_timeout = ENV['AUTOWORK_WORKER_STATUS_TIMEOUT_SECONDS']
      ENV['AUTOWORK_WORKER_STATUS_TIMEOUT_SECONDS'] = '2'
      task_root, task_folder = make_env_task
      repo = make_git_repo
      tmux = instance_double(Autowork::Tmux, discover_roles: role_panes(repo))
      allow(tmux).to receive(:send_prompt)

      stub_const('Autowork::TASK_ROOT', task_root)
      stub_const('Autowork::DOTS_REPO', repo)
      Autowork::RunSetup.new(%w[env 0003], tmux: tmux).prepare!

      files = Autowork::RunFiles.new(task_folder)
      state_store = Autowork::StateStore.new(files.state_path)
      state = state_store.read
      state['phase'] = 'waiting_for_pi_implement'
      state_store.write(state)
      File.write(files.status_path(1, 'pi', 'implement'), '{')
      sleeper = proc do |_seconds|
        File.write(File.join(repo, 'step1.txt'), "qa\n")
        File.write(files.status_path(1, 'pi', 'implement'), JSON.pretty_generate(
          'status' => 'done',
          'agent' => 'pi',
          'phase' => 'implement',
          'step' => 1,
          'summary' => 'created qa output'
        ))
      end

      expect { described_class.new(%w[env 0003], tmux: tmux, sleeper: sleeper).run }
        .to raise_error(Autowork::Error, /Worker status timeout/)

      commit_message = `git -C #{repo} log -1 --pretty=%s`.strip
      expect(commit_message).to eq('Step 1')
    ensure
      ENV['AUTOWORK_WORKER_STATUS_TIMEOUT_SECONDS'] = previous_timeout
    end

    it 'commits a completed pi-worker step and sends a claude-worker review prompt' do
      task_root, task_folder = make_env_task
      repo = make_git_repo
      tmux = instance_double(Autowork::Tmux, discover_roles: role_panes(repo))
      allow(tmux).to receive(:send_prompt)

      stub_const('Autowork::TASK_ROOT', task_root)
      stub_const('Autowork::DOTS_REPO', repo)
      Autowork::RunSetup.new(%w[env 0003], tmux: tmux).prepare!

      files = Autowork::RunFiles.new(task_folder)
      state_store = Autowork::StateStore.new(files.state_path)
      state = state_store.read
      state['phase'] = 'ready_to_commit_step'
      state_store.write(state)
      File.write(files.status_path(1, 'pi', 'implement'), JSON.pretty_generate(
        'status' => 'done',
        'agent' => 'pi',
        'phase' => 'implement',
        'step' => 1,
        'summary' => 'created qa output'
      ))
      File.write(File.join(repo, 'step1.txt'), "qa\n")

      expect { described_class.new(%w[env 0003], tmux: tmux).run }
        .to raise_error(Autowork::Error, /Worker status timeout/)

      state = state_store.read
      commit_message = `git -C #{repo} log -1 --pretty=%s`.strip
      expect(commit_message).to eq('Step 1')
      expect(tmux).to have_received(:send_prompt).with('%3', files.prompt_path('step1_claude_review1_request.md'))
      expect(state['status']).to eq('running')
      expect(state['phase']).to eq('waiting_for_claude_review')
      expect(state['last_commit']).to match(/\A[0-9a-f]{40}\z/)
    end

    it 'accepts a step when Claude reports no actionable findings' do
      task_root, task_folder = make_env_task
      repo = make_git_repo
      tmux = instance_double(Autowork::Tmux, discover_roles: role_panes(repo))
      allow(tmux).to receive(:send_prompt)

      stub_const('Autowork::TASK_ROOT', task_root)
      stub_const('Autowork::DOTS_REPO', repo)
      Autowork::RunSetup.new(%w[env 0003], tmux: tmux).prepare!

      files = Autowork::RunFiles.new(task_folder)
      state_store = Autowork::StateStore.new(files.state_path)
      state = state_store.read
      state['phase'] = 'waiting_for_claude_review'
      state['last_commit'] = 'a' * 40
      state['review_iteration'] = 1
      state_store.write(state)
      File.write(files.status_path(1, 'claude', 'review', 1), JSON.pretty_generate(
        'status' => 'done',
        'agent' => 'claude',
        'phase' => 'review',
        'step' => 1,
        'summary' => 'no findings',
        'findings' => []
      ))
      File.write(files.review_path(1, 1), "Summary: 0 BLOCKER / 0 MINOR / 1 PASS\n")

      described_class.new(%w[env 0003], tmux: tmux).run

      state = state_store.read
      expect(state['status']).to eq('done')
      expect(state['phase']).to eq('complete')
      expect(state['next_action']).to eq('none')
      expect(state.dig('steps', '1', 'status')).to eq('accepted')
      expect(File.read(files.final_checks_path)).to include('skipped')
      expect(File.read(files.final_summary_path)).to include('# Autowork final summary')
    end

    it 'does not advance when Claude writes status before the review artifact' do
      task_root, task_folder = make_env_task
      repo = make_git_repo
      tmux = instance_double(Autowork::Tmux, discover_roles: role_panes(repo))
      allow(tmux).to receive(:send_prompt)

      stub_const('Autowork::TASK_ROOT', task_root)
      stub_const('Autowork::DOTS_REPO', repo)
      Autowork::RunSetup.new(%w[env 0003], tmux: tmux).prepare!

      files = Autowork::RunFiles.new(task_folder)
      state_store = Autowork::StateStore.new(files.state_path)
      state = state_store.read
      state['phase'] = 'waiting_for_claude_review'
      state['last_commit'] = 'b' * 40
      state['review_iteration'] = 1
      state_store.write(state)
      File.write(files.status_path(1, 'claude', 'review', 1), JSON.pretty_generate(
        'status' => 'done',
        'agent' => 'claude',
        'phase' => 'review',
        'step' => 1,
        'summary' => 'status too early',
        'findings' => []
      ))

      expect { described_class.new(%w[env 0003], tmux: tmux).run }
        .to raise_error(Autowork::Error, /artifact is missing or empty/)

      expect(state_store.read['phase']).to eq('waiting_for_claude_review')
    end

    it 'sends a Pi classification prompt when Claude reports findings' do
      task_root, task_folder = make_env_task
      repo = make_git_repo
      tmux = instance_double(Autowork::Tmux, discover_roles: role_panes(repo))
      allow(tmux).to receive(:send_prompt)

      stub_const('Autowork::TASK_ROOT', task_root)
      stub_const('Autowork::DOTS_REPO', repo)
      Autowork::RunSetup.new(%w[env 0003], tmux: tmux).prepare!

      files = Autowork::RunFiles.new(task_folder)
      state_store = Autowork::StateStore.new(files.state_path)
      state = state_store.read
      state['phase'] = 'waiting_for_claude_review'
      state['last_commit'] = 'b' * 40
      state['review_iteration'] = 1
      state_store.write(state)
      File.write(files.status_path(1, 'claude', 'review', 1), JSON.pretty_generate(
        'status' => 'done',
        'agent' => 'claude',
        'phase' => 'review',
        'step' => 1,
        'summary' => 'one blocker',
        'findings' => [
          { 'id' => 'B1', 'severity' => 'BLOCKER', 'title' => 'Bug', 'body' => 'Broken', 'recommendation' => 'Fix it' }
        ]
      ))
      File.write(files.review_path(1, 1), "Summary: 1 BLOCKER / 0 MINOR / 0 PASS\n")

      expect { described_class.new(%w[env 0003], tmux: tmux).run }
        .to raise_error(Autowork::Error, /Worker status timeout/)

      state = state_store.read
      expect(tmux).to have_received(:send_prompt).with('%2', files.prompt_path('step1_pi_classify_review1_request.md'))
      expect(state['phase']).to eq('waiting_for_pi_classify')
      expect(state['current_findings'].first['id']).to eq('B1')
    end

    it 'sends a Claude debate prompt when Pi disputes a finding' do
      task_root, task_folder = make_env_task
      repo = make_git_repo
      tmux = instance_double(Autowork::Tmux, discover_roles: role_panes(repo))
      allow(tmux).to receive(:send_prompt)

      stub_const('Autowork::TASK_ROOT', task_root)
      stub_const('Autowork::DOTS_REPO', repo)
      Autowork::RunSetup.new(%w[env 0003], tmux: tmux).prepare!

      files = Autowork::RunFiles.new(task_folder)
      state_store = Autowork::StateStore.new(files.state_path)
      state = state_store.read
      state['phase'] = 'waiting_for_pi_classify'
      state['current_findings'] = [{ 'id' => 'B1', 'severity' => 'BLOCKER', 'title' => 'Bug', 'body' => 'Broken' }]
      state['review_iteration'] = 1
      state_store.write(state)
      File.write(files.resolution_path(1, 1), "B1 disputed\n")
      File.write(files.status_path(1, 'pi', 'classify', 1), JSON.pretty_generate(
        'status' => 'done',
        'agent' => 'pi',
        'phase' => 'classify',
        'step' => 1,
        'summary' => 'disputed blocker',
        'resolutions' => [
          { 'finding_id' => 'B1', 'decision' => 'dispute', 'rationale' => 'not reachable' }
        ]
      ))

      expect { described_class.new(%w[env 0003], tmux: tmux).run }
        .to raise_error(Autowork::Error, /Worker status timeout/)

      state = state_store.read
      expect(tmux).to have_received(:send_prompt).with('%3', files.prompt_path('step1_debate_B1_round1_claude_request.md'))
      expect(state['phase']).to eq('waiting_for_claude_debate')
      expect(state['debate_round']).to eq(1)
      expect(File.read(files.debate_path(1))).to include('B1')
    end

    it 'accepts a disputed finding when Claude agrees with Pi in debate' do
      task_root, task_folder = make_env_task
      repo = make_git_repo
      tmux = instance_double(Autowork::Tmux, discover_roles: role_panes(repo))
      allow(tmux).to receive(:send_prompt)

      stub_const('Autowork::TASK_ROOT', task_root)
      stub_const('Autowork::DOTS_REPO', repo)
      Autowork::RunSetup.new(%w[env 0003], tmux: tmux).prepare!

      files = Autowork::RunFiles.new(task_folder)
      state_store = Autowork::StateStore.new(files.state_path)
      state = state_store.read
      state['phase'] = 'waiting_for_claude_debate'
      state['current_findings'] = [{ 'id' => 'B1', 'severity' => 'BLOCKER', 'title' => 'Bug', 'body' => 'Broken' }]
      state['current_resolutions'] = [{ 'finding_id' => 'B1', 'decision' => 'dispute', 'rationale' => 'not reachable' }]
      state['current_debate_resolutions'] = [{ 'finding_id' => 'B1', 'decision' => 'dispute', 'rationale' => 'not reachable' }]
      state['debate_index'] = 0
      state['debate_round'] = 1
      state['review_iteration'] = 1
      state_store.write(state)
      File.write(files.debate_claude_result_path(1, 'B1', 1), "Claude agrees\n")
      File.write(files.status_path(1, 'claude', 'debate', '_B1_round1'), JSON.pretty_generate(
        'status' => 'done',
        'agent' => 'claude',
        'phase' => 'debate',
        'step' => 1,
        'summary' => 'agree with Pi',
        'debate' => { 'finding_id' => 'B1', 'round' => 1, 'decision' => 'agree_with_pi' }
      ))

      described_class.new(%w[env 0003], tmux: tmux).run

      state = state_store.read
      expect(state['phase']).to eq('complete')
      expect(state.dig('steps', '1', 'status')).to eq('accepted')
      expect(File.read(files.final_summary_path)).to include('Autowork final summary')
    end

    it 'sends a Pi debate prompt when Claude still disagrees' do
      task_root, task_folder = make_env_task
      repo = make_git_repo
      tmux = instance_double(Autowork::Tmux, discover_roles: role_panes(repo))
      allow(tmux).to receive(:send_prompt)

      stub_const('Autowork::TASK_ROOT', task_root)
      stub_const('Autowork::DOTS_REPO', repo)
      Autowork::RunSetup.new(%w[env 0003], tmux: tmux).prepare!

      files = Autowork::RunFiles.new(task_folder)
      state_store = Autowork::StateStore.new(files.state_path)
      state = state_store.read
      state['phase'] = 'waiting_for_claude_debate'
      state['current_debate_resolutions'] = [{ 'finding_id' => 'B1', 'decision' => 'dispute', 'rationale' => 'not reachable' }]
      state['debate_index'] = 0
      state['debate_round'] = 1
      state['review_iteration'] = 1
      state_store.write(state)
      File.write(files.debate_claude_result_path(1, 'B1', 1), "Still disagree\n")
      File.write(files.status_path(1, 'claude', 'debate', '_B1_round1'), JSON.pretty_generate(
        'status' => 'done',
        'agent' => 'claude',
        'phase' => 'debate',
        'step' => 1,
        'summary' => 'still disagree',
        'debate' => { 'finding_id' => 'B1', 'round' => 1, 'decision' => 'still_disagree' }
      ))

      expect { described_class.new(%w[env 0003], tmux: tmux).run }
        .to raise_error(Autowork::Error, /Worker status timeout/)

      expect(tmux).to have_received(:send_prompt).with('%2', files.prompt_path('step1_debate_B1_round1_pi_request.md'))
      expect(state_store.read['phase']).to eq('waiting_for_pi_debate')
    end

    it 'pauses after the configured debate round limit when agents still disagree' do
      task_root, task_folder = make_env_task
      repo = make_git_repo
      tmux = instance_double(Autowork::Tmux, discover_roles: role_panes(repo))
      allow(tmux).to receive(:send_prompt)

      stub_const('Autowork::TASK_ROOT', task_root)
      stub_const('Autowork::DOTS_REPO', repo)
      Autowork::RunSetup.new(%w[env 0003], tmux: tmux).prepare!

      files = Autowork::RunFiles.new(task_folder)
      config = YAML.safe_load(File.read(files.config_path))
      config['max_debate_rounds_per_disagreement'] = 1
      File.write(files.config_path, config.to_yaml)
      state_store = Autowork::StateStore.new(files.state_path)
      state = state_store.read
      state['phase'] = 'waiting_for_pi_debate'
      state['current_debate_resolutions'] = [{ 'finding_id' => 'B1', 'decision' => 'dispute', 'rationale' => 'not reachable' }]
      state['debate_index'] = 0
      state['debate_round'] = 1
      state['review_iteration'] = 1
      state_store.write(state)
      File.write(files.debate_pi_result_path(1, 'B1', 1), "Still disagree\n")
      File.write(files.status_path(1, 'pi', 'debate', '_B1_round1'), JSON.pretty_generate(
        'status' => 'done',
        'agent' => 'pi',
        'phase' => 'debate',
        'step' => 1,
        'summary' => 'still disagree',
        'debate' => { 'finding_id' => 'B1', 'round' => 1, 'decision' => 'still_disagree', 'rationale' => 'not reachable' }
      ))

      expect { described_class.new(%w[env 0003], tmux: tmux).run }
        .to raise_error(Autowork::Error, /still disagree/)

      state = state_store.read
      expect(state['status']).to eq('paused')
      expect(state['paused_reason']).to include('after 1 debate round')
    end

    it 'tells Claude step reviewers not to run full RuboCop or RSpec' do
      task_root, task_folder = make_env_task
      repo = make_git_repo
      tmux = instance_double(Autowork::Tmux, discover_roles: role_panes(repo))

      stub_const('Autowork::TASK_ROOT', task_root)
      stub_const('Autowork::DOTS_REPO', repo)
      Autowork::RunSetup.new(%w[env 0003], tmux: tmux).prepare!

      files = Autowork::RunFiles.new(task_folder)
      prompt = Autowork::PromptWriter.new(files, Autowork::TaskResolver.new(%w[env 0003], cwd: repo).resolve, Autowork::GitRepo.new(repo)).claude_review(1, 1, 'a' * 40)
      text = File.read(prompt)

      expect(text).to include('Do not run full RuboCop or full RSpec during normal step review')
      expect(text).to include('`/autowork` runs full final checks after all planned steps are accepted')
    end

    it 'tells Claude final-check reviewers not to rerun full checks' do
      task_root, task_folder = make_env_task
      repo = make_git_repo
      tmux = instance_double(Autowork::Tmux, discover_roles: role_panes(repo))

      stub_const('Autowork::TASK_ROOT', task_root)
      stub_const('Autowork::DOTS_REPO', repo)
      Autowork::RunSetup.new(%w[env 0003], tmux: tmux).prepare!

      files = Autowork::RunFiles.new(task_folder)
      prompt = Autowork::PromptWriter.new(files, Autowork::TaskResolver.new(%w[env 0003], cwd: repo).resolve, Autowork::GitRepo.new(repo)).claude_final_check_review(1, ['a' * 40])
      text = File.read(prompt)

      expect(text).to include('Do not rerun full RuboCop or full RSpec here')
      expect(text).to include('inspect `final_checks.md` and the fix commits')
    end

    it 'removes stale review artifacts before sending a new Claude review prompt' do
      task_root, task_folder = make_env_task
      repo = make_git_repo
      tmux = instance_double(Autowork::Tmux, discover_roles: role_panes(repo))
      allow(tmux).to receive(:send_prompt)

      stub_const('Autowork::TASK_ROOT', task_root)
      stub_const('Autowork::DOTS_REPO', repo)
      Autowork::RunSetup.new(%w[env 0003], tmux: tmux).prepare!

      files = Autowork::RunFiles.new(task_folder)
      state_store = Autowork::StateStore.new(files.state_path)
      state = state_store.read
      state['phase'] = 'ready_to_send_claude_review'
      state['last_commit'] = 'c' * 40
      state['review_iteration'] = 1
      state_store.write(state)
      File.write(files.review_path(1, 1), 'stale review')
      File.write(files.status_path(1, 'claude', 'review', 1), JSON.pretty_generate(
        'status' => 'done',
        'agent' => 'claude',
        'phase' => 'review',
        'step' => 1,
        'summary' => 'stale status',
        'findings' => []
      ))

      expect { described_class.new(%w[env 0003], tmux: tmux).run }
        .to raise_error(Autowork::Error, /Worker status timeout/)

      expect(File.file?(files.review_path(1, 1))).to be(false)
      expect(File.file?(files.status_path(1, 'claude', 'review', 1))).to be(false)
      expect(state_store.read['phase']).to eq('waiting_for_claude_review')
    end

    it 'sends a Pi final-check fix prompt when final checks fail' do
      task_root, task_folder = make_env_task
      repo = make_git_repo
      tmux = instance_double(Autowork::Tmux, discover_roles: role_panes(repo))
      allow(tmux).to receive(:send_prompt)

      stub_const('Autowork::TASK_ROOT', task_root)
      stub_const('Autowork::DOTS_REPO', repo)
      Autowork::RunSetup.new(%w[env 0003], tmux: tmux).prepare!

      files = Autowork::RunFiles.new(task_folder)
      config = YAML.safe_load(File.read(files.config_path))
      config['final_check_commands'] = ['test -f fixed.txt']
      File.write(files.config_path, config.to_yaml)
      state_store = Autowork::StateStore.new(files.state_path)
      state = state_store.read
      state['phase'] = 'ready_to_run_final_checks'
      state_store.write(state)

      expect { described_class.new(%w[env 0003], tmux: tmux).run }
        .to raise_error(Autowork::Error, /Worker status timeout/)

      state = state_store.read
      expect(tmux).to have_received(:send_prompt).with('%2', files.prompt_path('final_checks_pi_fix1_request.md'))
      expect(state['phase']).to eq('waiting_for_pi_final_check_fix')
      expect(state['final_check_fix_iteration']).to eq(1)
      expect(File.read(files.final_checks_path)).to include('test -f fixed.txt')
    end

    it 'reruns final checks without committing when Pi final-check fix makes no repo changes' do
      task_root, task_folder = make_env_task
      repo = make_git_repo
      tmux = instance_double(Autowork::Tmux, discover_roles: role_panes(repo))
      allow(tmux).to receive(:send_prompt)

      stub_const('Autowork::TASK_ROOT', task_root)
      stub_const('Autowork::DOTS_REPO', repo)
      Autowork::RunSetup.new(%w[env 0003], tmux: tmux).prepare!

      files = Autowork::RunFiles.new(task_folder)
      config = YAML.safe_load(File.read(files.config_path))
      config['final_check_commands'] = ['true']
      File.write(files.config_path, config.to_yaml)
      state_store = Autowork::StateStore.new(files.state_path)
      state = state_store.read
      state['phase'] = 'waiting_for_pi_final_check_fix'
      state['final_check_fix_iteration'] = 1
      state['final_checks'] = [{ 'command' => 'true', 'status' => 'failed', 'exit_status' => 1, 'stdout' => '', 'stderr' => '' }]
      state_store.write(state)
      File.write(files.status_path(0, 'pi', 'final_checks_fix', 1), JSON.pretty_generate(
        'status' => 'done',
        'agent' => 'pi',
        'phase' => 'final_checks',
        'step' => 0,
        'summary' => 'no repo fix needed'
      ))

      described_class.new(%w[env 0003], tmux: tmux).run

      state = state_store.read
      expect(state['phase']).to eq('complete')
      expect(state['final_check_fix_commits']).to be_nil
      expect(`git -C #{repo} log --oneline 2>/dev/null`.strip).to be_empty
      expect(File.read(files.final_checks_path)).to include('Status: passed')
    end

    it 'commits a final-check fix, reruns checks, and sends Claude final-check review' do
      task_root, task_folder = make_env_task
      repo = make_git_repo
      tmux = instance_double(Autowork::Tmux, discover_roles: role_panes(repo))
      allow(tmux).to receive(:send_prompt)

      stub_const('Autowork::TASK_ROOT', task_root)
      stub_const('Autowork::DOTS_REPO', repo)
      Autowork::RunSetup.new(%w[env 0003], tmux: tmux).prepare!

      files = Autowork::RunFiles.new(task_folder)
      config = YAML.safe_load(File.read(files.config_path))
      config['final_check_commands'] = ['test -f fixed.txt']
      File.write(files.config_path, config.to_yaml)
      state_store = Autowork::StateStore.new(files.state_path)
      state = state_store.read
      state['phase'] = 'waiting_for_pi_final_check_fix'
      state['final_check_fix_iteration'] = 1
      state['final_checks'] = [{ 'command' => 'test -f fixed.txt', 'status' => 'failed', 'exit_status' => 1, 'stdout' => '', 'stderr' => '' }]
      state_store.write(state)
      File.write(files.status_path(0, 'pi', 'final_checks_fix', 1), JSON.pretty_generate(
        'status' => 'done',
        'agent' => 'pi',
        'phase' => 'final_checks',
        'step' => 0,
        'summary' => 'fixed final checks'
      ))
      File.write(File.join(repo, 'fixed.txt'), "fixed\n")

      expect { described_class.new(%w[env 0003], tmux: tmux).run }
        .to raise_error(Autowork::Error, /Worker status timeout/)

      state = state_store.read
      commit_message = `git -C #{repo} log -1 --pretty=%s`.strip
      expect(commit_message).to eq('Final checks fix 1')
      expect(state['final_check_fix_commits'].first).to match(/\A[0-9a-f]{40}\z/)
      expect(tmux).to have_received(:send_prompt).with('%3', files.prompt_path('final_checks_claude_review1_request.md'))
      expect(state['phase']).to eq('waiting_for_claude_final_check_review')
    end

    it 'completes after Claude accepts final-check fix commits' do
      task_root, task_folder = make_env_task
      repo = make_git_repo
      tmux = instance_double(Autowork::Tmux, discover_roles: role_panes(repo))
      allow(tmux).to receive(:send_prompt)

      stub_const('Autowork::TASK_ROOT', task_root)
      stub_const('Autowork::DOTS_REPO', repo)
      Autowork::RunSetup.new(%w[env 0003], tmux: tmux).prepare!

      files = Autowork::RunFiles.new(task_folder)
      state_store = Autowork::StateStore.new(files.state_path)
      state = state_store.read
      state['phase'] = 'waiting_for_claude_final_check_review'
      state['final_check_review_iteration'] = 1
      state['final_check_fix_commits'] = ['a' * 40]
      state['final_checks'] = [{ 'command' => 'test -f fixed.txt', 'status' => 'passed', 'exit_status' => 0, 'stdout' => '', 'stderr' => '' }]
      state_store.write(state)
      File.write(files.final_check_review_path(1), "Summary: 0 BLOCKER / 0 MINOR / 1 PASS\n")
      File.write(files.status_path(0, 'claude', 'final_checks_review', 1), JSON.pretty_generate(
        'status' => 'done',
        'agent' => 'claude',
        'phase' => 'final_checks',
        'step' => 0,
        'summary' => 'final-check fixes accepted',
        'findings' => []
      ))

      described_class.new(%w[env 0003], tmux: tmux).run

      state = state_store.read
      expect(state['phase']).to eq('complete')
      expect(state['final_check_reviewed']).to be(true)
      expect(File.read(files.final_summary_path)).to include('Final checks fix 1')
      expect(File.read(files.final_summary_path)).to include('Final checks review 1')
    end

    it 'commits accepted fixes and sends a follow-up Claude review' do
      task_root, task_folder = make_env_task
      repo = make_git_repo
      tmux = instance_double(Autowork::Tmux, discover_roles: role_panes(repo))
      allow(tmux).to receive(:send_prompt)

      stub_const('Autowork::TASK_ROOT', task_root)
      stub_const('Autowork::DOTS_REPO', repo)
      Autowork::RunSetup.new(%w[env 0003], tmux: tmux).prepare!

      files = Autowork::RunFiles.new(task_folder)
      state_store = Autowork::StateStore.new(files.state_path)
      state = state_store.read
      state['phase'] = 'ready_to_commit_fix'
      state['last_commit'] = 'c' * 40
      state['review_iteration'] = 1
      state['fix_iteration'] = 1
      state['accepted_resolutions'] = [{ 'finding_id' => 'B1', 'decision' => 'accept', 'rationale' => 'fix it' }]
      state_store.write(state)
      File.write(files.status_path(1, 'pi', 'fix', 1), JSON.pretty_generate(
        'status' => 'done',
        'agent' => 'pi',
        'phase' => 'fix',
        'step' => 1,
        'summary' => 'fixed blocker'
      ))
      File.write(File.join(repo, 'fix.txt'), "fix\n")

      expect { described_class.new(%w[env 0003], tmux: tmux).run }
        .to raise_error(Autowork::Error, /Worker status timeout/)

      state = state_store.read
      commit_message = `git -C #{repo} log -1 --pretty=%s`.strip
      expect(commit_message).to eq('Step 1 fix 1')
      expect(tmux).to have_received(:send_prompt).with('%3', files.prompt_path('step1_claude_review2_request.md'))
      expect(state['phase']).to eq('waiting_for_claude_review')
      expect(state['review_iteration']).to eq(2)
    end
  end

  describe Autowork::Doctor do
    it 'reports abstract repo, pane, delivery, and status-validator health' do
      repo = make_git_repo
      tmux = instance_double(Autowork::Tmux, discover_roles: role_panes(repo))
      allow(tmux).to receive(:send_text)
      output = StringIO.new

      original_stdout = $stdout
      $stdout = output
      described_class.new([], tmux: tmux, cwd: repo).run
      $stdout = original_stdout

      text = output.string
      expect(text).to include('Autowork doctor')
      expect(text).to include('helper:')
      expect(text).to include("repo_dir: #{File.realpath(repo)}")
      expect(text).to include('worktree: clean')
      expect(text).to include('tmux_panes: ok')
      expect(text).to include('prompt_delivery: ready')
      expect(text).to include('prompt_delivery_send_test: enabled')
      expect(text).to include('prompt_delivery_send_test: sent to pi-worker and claude-worker')
      expect(text).to include('status_json_validator: ok')
    ensure
      $stdout = original_stdout if original_stdout
    end

    it 'can skip doctor test lines when requested' do
      repo = make_git_repo
      roles = role_panes(repo)
      tmux = instance_double(Autowork::Tmux, discover_roles: roles)
      allow(tmux).to receive(:send_text)
      output = StringIO.new

      original_stdout = $stdout
      $stdout = output
      described_class.new(%w[--no-send-test], tmux: tmux, cwd: repo).run
      $stdout = original_stdout

      expect(tmux).not_to have_received(:send_text)
      expect(output.string).to include('prompt_delivery_send_test: skipped (--no-send-test)')
    ensure
      $stdout = original_stdout if original_stdout
    end

    it 'rejects task arguments because doctor is not task QA' do
      repo = make_git_repo

      expect { described_class.new(%w[my_autowork_qa 0001], cwd: repo).run }
        .to raise_error(Autowork::Error, /Usage: autowork doctor/)
    end
  end
end
