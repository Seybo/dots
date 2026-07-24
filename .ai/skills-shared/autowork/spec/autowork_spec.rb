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

  def commit_file(repo, path, content, message)
    full_path = File.join(repo, path)
    FileUtils.mkdir_p(File.dirname(full_path))
    File.write(full_path, content)
    system('git', '-C', repo, 'add', path, out: File::NULL, err: File::NULL)
    system('git', '-C', repo, 'commit', '-m', message, out: File::NULL, err: File::NULL)
    `git -C #{repo} rev-parse HEAD`.strip
  end

  def add_origin_remote(repo)
    origin = File.join(@tmpdir, 'origin.git')
    system('git', 'init', '--bare', origin, out: File::NULL, err: File::NULL)
    system('git', '-C', repo, 'remote', 'add', 'origin', origin, out: File::NULL, err: File::NULL)
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

  describe Autowork::GitRepo do
    it 'squashes review commits onto the round start with the requested message' do
      repo = make_git_repo
      base_sha = commit_file(repo, 'base.txt', "base\n", 'base')
      commit_file(repo, 'first.txt', "first\n", 'first review update')
      commit_file(repo, 'second.txt', "second\n", 'second review update')

      squashed_sha = described_class.new(repo).squash_commits(base_sha, 'Add review updates #1')

      expect(`git -C #{repo} log -1 --format=%s`.strip).to eq('Add review updates #1')
      expect(`git -C #{repo} rev-list --count HEAD`.strip).to eq('2')
      expect(squashed_sha).to eq(`git -C #{repo} rev-parse HEAD`.strip)
      expect(File.read(File.join(repo, 'first.txt'))).to eq("first\n")
      expect(File.read(File.join(repo, 'second.txt'))).to eq("second\n")
      expect(described_class.new(repo)).to be_clean
    end
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

    it 'does not infer a task from an arbitrary branch name' do
      task_root, = make_env_task
      dots_repo = make_git_repo
      system('git', '-C', dots_repo, 'checkout', '-b', 'release/2024-fixes', out: File::NULL, err: File::NULL)

      stub_const('Autowork::TASK_ROOT', task_root)
      stub_const('Autowork::DOTS_REPO', dots_repo)

      expect { described_class.new([], cwd: dots_repo).resolve }
        .to raise_error(Autowork::Error, /Could not infer task id/)
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

    it 'supports arbitrary numbered workspaces for any registered project' do
      task_root = File.join(@tmpdir, '_tasks')
      FileUtils.mkdir_p(File.join(task_root, 'shaka_trp', '12345-test-task'))

      stub_const('Autowork::TASK_ROOT', task_root)

      context = described_class.new(%w[shaka_trp28 12345], cwd: @tmpdir).resolve

      expect(context.project).to eq('shaka_trp')
      expect(context.code_dir).to eq('/Volumes/dev/projects/shaka/trp/28th')
    end

    it 'infers a numbered workspace from the current project path' do
      task_root = File.join(@tmpdir, '_tasks')
      FileUtils.mkdir_p(File.join(task_root, 'shaka_trp', '12345-test-task'))

      stub_const('Autowork::TASK_ROOT', task_root)

      context = described_class.new(['12345'], cwd: '/Volumes/dev/projects/shaka/trp/7th/plugins').resolve

      expect(context.project).to eq('shaka_trp')
      expect(context.code_dir).to eq('/Volumes/dev/projects/shaka/trp/7th')
    end

    it 'infers a direct checkout project and resolves its local task id' do
      task_root = File.join(@tmpdir, '_tasks')
      repo = File.join(@tmpdir, 'rails')
      task_folder = File.join(task_root, 'rails', '0001-fix-docs')
      registry = File.join(@tmpdir, 'projects.yml')
      FileUtils.mkdir_p(File.join(repo, 'docs'))
      FileUtils.mkdir_p(task_folder)
      File.write(registry, <<~YAML)
        projects:
          rails:
            checkout_layout: direct
            checkout_path: #{repo}
            task_provider: local
      YAML

      stub_const('Autowork::TASK_ROOT', task_root)

      context = described_class.new(['0001'], cwd: File.join(repo, 'docs'), projects_file: registry).resolve

      expect(context.project).to eq('rails')
      expect(context.code_dir).to eq(repo)
      expect(context.task_folder).to eq(task_folder)
    end

    it 'accepts a full base branch/ref as the second argument when project is inferred' do
      task_root, task_folder = make_env_task(task_id: '1234')
      dots_repo = make_git_repo

      stub_const('Autowork::TASK_ROOT', task_root)
      stub_const('Autowork::DOTS_REPO', dots_repo)

      context = described_class.new(%w[1234 mikhail/sc-1233/parent-branch], cwd: dots_repo).resolve

      expect(context.task_folder).to eq(task_folder)
      expect(context.review_base_ref).to eq('mikhail/sc-1233/parent-branch')
    end

    it 'accepts a full base branch/ref as the third argument when project is explicit' do
      task_root, = make_env_task(task_id: '1234')
      dots_repo = make_git_repo

      stub_const('Autowork::TASK_ROOT', task_root)
      stub_const('Autowork::DOTS_REPO', dots_repo)

      context = described_class.new(%w[env 1234 parent/feature], cwd: dots_repo).resolve

      expect(context.project).to eq('env')
      expect(context.review_base_ref).to eq('parent/feature')
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

    it 'accepts follow-up review resolutions and rejects deprecated defer_minor' do
      valid = validator.validate_hash(
        {
          'status' => 'done',
          'agent' => 'pi',
          'phase' => 'classify',
          'step' => 1,
          'summary' => 'classified',
          'resolutions' => [
            { 'finding_id' => 'B1', 'decision' => 'follow_up', 'rationale' => 'outside this task and non-minor' }
          ]
        }
      )
      invalid = validator.validate_hash(
        {
          'status' => 'done',
          'agent' => 'pi',
          'phase' => 'classify',
          'step' => 1,
          'summary' => 'classified',
          'resolutions' => [
            { 'finding_id' => 'M1', 'decision' => 'defer_minor', 'rationale' => 'later' }
          ]
        }
      )

      expect(valid).to be_valid
      expect(invalid).not_to be_valid
      expect(invalid.errors).to include('resolutions[0].decision is invalid')
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

    it 'rejects a manager fix review status without findings' do
      result = validator.validate_hash(
        {
          'status' => 'done',
          'agent' => 'claude',
          'phase' => 'manager_fix_review',
          'step' => 0,
          'summary' => 'accepted'
        }
      )

      expect(result).not_to be_valid
      expect(result.errors).to include('findings is required for completed manager_fix_review')
    end

    it 'accepts a manager fix review escalation without findings' do
      result = validator.validate_hash(
        {
          'status' => 'needs_user',
          'agent' => 'claude',
          'phase' => 'manager_fix_review',
          'step' => 0,
          'summary' => 'Need a product decision',
          'question' => 'Should this behavior be changed?'
        }
      )

      expect(result).to be_valid
    end

    it 'accepts a failed manager fix review without findings' do
      result = validator.validate_hash(
        {
          'status' => 'failed',
          'agent' => 'claude',
          'phase' => 'manager_fix_review',
          'step' => 0,
          'summary' => 'The review could not complete'
        }
      )

      expect(result).to be_valid
    end

    it 'reports invalid JSON status files' do
      path = File.join(@tmpdir, 'status.json')
      File.write(path, '{ nope')

      result = validator.validate_file(path)

      expect(result).not_to be_valid
      expect(result.errors.join).to include('invalid JSON')
    end
  end

  describe Autowork::ManagerFindingsValidator do
    let(:validator) { described_class.new }

    it 'accepts a complete actionable manager finding set' do
      result = validator.validate_hash(
        'summary' => 'Manager context found a production gap',
        'findings' => [{
          'id' => 'MR1',
          'severity' => 'BLOCKER',
          'title' => 'Wrong campaign attribution',
          'body' => 'Current state is not a campaign event',
          'recommendation' => 'Use the campaign-scoped endpoint'
        }],
        'followups' => []
      )

      expect(result).to be_valid
    end

    it 'rejects severities outside the manager review contract' do
      result = validator.validate_hash(
        'summary' => 'Manager context found a production gap',
        'findings' => [{
          'id' => 'MR1',
          'severity' => 'HIGH',
          'title' => 'Wrong campaign attribution',
          'body' => 'Current state is not a campaign event',
          'recommendation' => 'Use the campaign-scoped endpoint'
        }]
      )

      expect(result).not_to be_valid
    end

    it 'rejects empty, incomplete, and non-actionable finding input' do
      result = validator.validate_hash('summary' => '', 'findings' => [])

      expect(result).not_to be_valid
      expect(result.errors).to include('summary must be a non-empty string', 'findings must be a non-empty array')
    end
  end

  describe Autowork::RunFiles do
    it 'creates the expected autowork-log subdirectories' do
      task_folder = File.join(@tmpdir, 'task')
      files = described_class.new(task_folder)

      files.mkdirs

      expect(File.directory?(files.log_dir)).to be(true)
      %w[control prompts reviews debates resolutions super_fixes manager_reviews manager_fixes status].each do |name|
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

    it 'submits prompt text literally, then sends Enter separately' do
      tmux = described_class.new
      prompt_file = '/tmp/autowork prompt.md'

      expect(Autowork::Shell).to receive(:capture!)
        .with('tmux', 'send-keys', '-t', '%3', '-l', "Please read and follow: #{prompt_file}")
        .ordered
      expect(tmux).to receive(:sleep).with(Autowork::Tmux::DEFAULT_SUBMIT_DELAY_SECONDS).ordered
      expect(Autowork::Shell).to receive(:capture!)
        .with('tmux', 'send-keys', '-t', '%3', 'Enter')
        .ordered

      tmux.send_prompt('%3', prompt_file)
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

    it 'refuses to initialize a direct project on master' do
      task_root = File.join(@tmpdir, '_tasks')
      repo = make_git_repo
      task_folder = File.join(task_root, 'rails', '0001-fix-docs')
      registry = File.join(@tmpdir, 'projects.yml')
      FileUtils.mkdir_p(task_folder)
      File.write(File.join(task_folder, 'task.md'), "# Task\n")
      File.write(File.join(task_folder, 'steps.md'), "## Step 1: Fix docs\n")
      File.write(registry, <<~YAML)
        projects:
          rails:
            checkout_layout: direct
            checkout_path: #{repo}
            task_provider: local
      YAML
      tmux = instance_double(Autowork::Tmux, discover_roles: role_panes(repo))

      stub_const('Autowork::TASK_ROOT', task_root)
      stub_const('Autowork::PROJECTS_FILE', registry)

      expect { Autowork::RunSetup.new(%w[rails 0001], tmux: tmux).prepare! }
        .to raise_error(Autowork::Error, /protected branch "master"/)
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
      expect(config['branch_name']).not_to be_empty
      expect(config['starting_head_commit']).to be_nil
      expect(config['super_review_status_timeout_minutes']).to eq(20)
      expect(config['max_total_commits']).to eq(15)
      expect(config['run_final_super_review']).to eq(true)
      expect(%w[main master]).to include(config['review_base_ref'])
      expect(config['original_review_base_ref']).to eq(config['review_base_ref'])
      expect(config['original_review_base_commit']).to eq(config['review_base_commit'])
      expect(state['status']).to eq('initialized')
      expect(state['original_review_base_ref']).to eq(config['original_review_base_ref'])
      expect(state['review_base_ref']).to eq(config['review_base_ref'])
      expect(state['current_step']).to eq(1)
      expect(prompt).to include('as `pi-worker`')
      expect(prompt).to include('Implement only `## Step 1`')
    end

    it 'stores an explicit final super-review base ref and commit in config' do
      task_root, task_folder = make_env_task
      repo = make_git_repo
      base_sha = commit_file(repo, 'base.txt', "base\n", 'base')
      system('git', '-C', repo, 'branch', 'parent-feature', out: File::NULL, err: File::NULL)
      tmux = instance_double(Autowork::Tmux, discover_roles: role_panes(repo))

      stub_const('Autowork::TASK_ROOT', task_root)
      stub_const('Autowork::DOTS_REPO', repo)
      allow(Autowork::Tmux).to receive(:new).and_return(tmux)

      described_class.new(%w[env 0003 parent-feature]).run

      config = YAML.safe_load(File.read(Autowork::RunFiles.new(task_folder).config_path))
      expect(config['starting_head_commit']).to eq(base_sha)
      expect(config['original_review_base_ref']).to eq('parent-feature')
      expect(config['original_review_base_commit']).to eq(base_sha)
      expect(config['review_base_ref']).to eq('parent-feature')
      expect(config['review_base_ref_is_explicit']).to eq(true)
      expect(config['review_base_commit']).to eq(base_sha)
    end
  end

  describe Autowork::Orchestrator do
    around do |example|
      previous = ENV['AUTOWORK_WORKER_STATUS_TIMEOUT_SECONDS']
      previous_super = ENV['AUTOWORK_SUPER_REVIEW_STATUS_TIMEOUT_SECONDS']
      ENV['AUTOWORK_WORKER_STATUS_TIMEOUT_SECONDS'] = '0'
      ENV['AUTOWORK_SUPER_REVIEW_STATUS_TIMEOUT_SECONDS'] = '0'
      example.run
    ensure
      ENV['AUTOWORK_WORKER_STATUS_TIMEOUT_SECONDS'] = previous
      ENV['AUTOWORK_SUPER_REVIEW_STATUS_TIMEOUT_SECONDS'] = previous_super
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

    it 'prints a readable waiting-stage banner with the current step title' do
      task_root, = make_env_task
      repo = make_git_repo
      tmux = instance_double(Autowork::Tmux, discover_roles: role_panes(repo))
      allow(tmux).to receive(:send_prompt)

      stub_const('Autowork::TASK_ROOT', task_root)
      stub_const('Autowork::DOTS_REPO', repo)

      output = StringIO.new
      original_stdout = $stdout
      $stdout = output
      begin
        expect { described_class.new(%w[env 0003], tmux: tmux).run }
          .to raise_error(Autowork::Error, /Worker status timeout/)
      ensure
        $stdout = original_stdout
      end

      expect(output.string).to include("==================\n[PI WORKER IMPLEMENTATION — Step 1: First slice]\n==================")
    end

    it 'pauses before committing when the total commit limit is reached' do
      task_root, task_folder = make_env_task
      repo = make_git_repo
      tmux = instance_double(Autowork::Tmux, discover_roles: role_panes(repo))

      stub_const('Autowork::TASK_ROOT', task_root)
      stub_const('Autowork::DOTS_REPO', repo)
      Autowork::RunSetup.new(%w[env 0003], tmux: tmux).prepare!

      files = Autowork::RunFiles.new(task_folder)
      state_store = Autowork::StateStore.new(files.state_path)
      state = state_store.read
      state['phase'] = 'ready_to_commit_step'
      state['steps']['1']['commits'] = Array.new(15, 'a' * 40)
      state_store.write(state)
      File.write(File.join(repo, 'pending.txt'), "pending\n")

      expect { described_class.new(%w[env 0003], tmux: tmux).run }
        .to raise_error(Autowork::Error, /Autowork commit limit reached: 15\/15/)

      expect(state_store.read['status']).to eq('paused')
      expect(File.read(files.paused_reason_path)).to include('Increase max_total_commits explicitly')
      expect(File.exist?(File.join(repo, 'pending.txt'))).to be(true)
    end

    it 'pauses before advancing when an explicit review base advances' do
      task_root, task_folder = make_env_task
      repo = make_git_repo
      commit_file(repo, 'base.txt', "base\n", 'base')
      system('git', '-C', repo, 'branch', 'parent-task', out: File::NULL, err: File::NULL)
      tmux = instance_double(Autowork::Tmux, discover_roles: role_panes(repo))
      allow(tmux).to receive(:send_prompt)

      stub_const('Autowork::TASK_ROOT', task_root)
      stub_const('Autowork::DOTS_REPO', repo)
      Autowork::RunSetup.new(%w[env 0003 parent-task], tmux: tmux).prepare!

      files = Autowork::RunFiles.new(task_folder)
      state_store = Autowork::StateStore.new(files.state_path)
      state = state_store.read
      state['phase'] = 'step_accepted'
      state.dig('steps', '1')['status'] = 'accepted'
      state_store.write(state)
      commit_file(repo, 'base.txt', "base advanced\n", 'advance base')
      system('git', '-C', repo, 'branch', '-f', 'parent-task', 'HEAD', out: File::NULL, err: File::NULL)

      expect { described_class.new(%w[env 0003 parent-task], tmux: tmux).run }
        .to raise_error(Autowork::Error, /Review base ref parent-task advanced/)

      state = state_store.read
      expect(state['status']).to eq('paused')
      expect(state['paused_reason']).to include('autowork update-base')
      expect(File.read(files.paused_reason_path)).to include('parent-task advanced')
    end

    it 'updates the stored review base explicitly without rebasing' do
      task_root, task_folder = make_env_task
      repo = make_git_repo
      commit_file(repo, 'base.txt', "base\n", 'base')
      system('git', '-C', repo, 'branch', 'parent-task', out: File::NULL, err: File::NULL)
      tmux = instance_double(Autowork::Tmux, discover_roles: role_panes(repo))

      stub_const('Autowork::TASK_ROOT', task_root)
      stub_const('Autowork::DOTS_REPO', repo)
      Autowork::RunSetup.new(%w[env 0003 parent-task], tmux: tmux).prepare!

      files = Autowork::RunFiles.new(task_folder)
      state_store = Autowork::StateStore.new(files.state_path)
      state = state_store.read
      state['status'] = 'paused'
      state['paused_reason'] = 'base advanced'
      state_store.write(state)
      File.write(files.paused_reason_path, "paused\n")
      new_base_sha = commit_file(repo, 'main.txt', "main\n", 'main base')
      system('git', '-C', repo, 'branch', 'new-base', 'HEAD', out: File::NULL, err: File::NULL)

      Autowork::BaseRefUpdater.new([task_folder, 'new-base']).run

      config = YAML.safe_load(File.read(files.config_path))
      state = state_store.read
      expect(config['original_review_base_ref']).to eq('parent-task')
      expect(config['original_review_base_commit']).not_to eq(new_base_sha)
      expect(config['review_base_ref']).to eq('new-base')
      expect(config['review_base_commit']).to eq(new_base_sha)
      expect(state['status']).to eq('running')
      expect(state['original_review_base_ref']).to eq('parent-task')
      expect(state['review_base_ref']).to eq('new-base')
      expect(File.file?(files.paused_reason_path)).to be(false)
    end

    it 'rebases onto the configured review base when no new base is passed' do
      task_root, task_folder = make_env_task
      repo = make_git_repo
      add_origin_remote(repo)
      base_sha = commit_file(repo, 'base.txt', "base\n", 'base')
      system('git', '-C', repo, 'branch', 'parent-task', base_sha, out: File::NULL, err: File::NULL)
      system('git', '-C', repo, 'checkout', '-b', 'mikhail/sc-0003/task', 'parent-task', out: File::NULL, err: File::NULL)
      tmux = instance_double(Autowork::Tmux, discover_roles: role_panes(repo))

      stub_const('Autowork::TASK_ROOT', task_root)
      stub_const('Autowork::DOTS_REPO', repo)
      Autowork::RunSetup.new(%w[env 0003 parent-task], tmux: tmux).prepare!
      commit_file(repo, 'task.txt', "task\n", 'task work')
      system('git', '-C', repo, 'checkout', 'parent-task', out: File::NULL, err: File::NULL)
      advanced_base_sha = commit_file(repo, 'base.txt', "base advanced\n", 'advance parent')
      system('git', '-C', repo, 'checkout', 'mikhail/sc-0003/task', out: File::NULL, err: File::NULL)

      Autowork::BaseRebaser.new([], cwd: repo).run

      files = Autowork::RunFiles.new(task_folder)
      config = YAML.safe_load(File.read(files.config_path))
      state = Autowork::StateStore.new(files.state_path).read
      expect(config['original_review_base_ref']).to eq('parent-task')
      expect(config['original_review_base_commit']).to eq(base_sha)
      expect(config['review_base_ref']).to eq('parent-task')
      expect(config['review_base_commit']).to eq(advanced_base_sha)
      expect(state['original_review_base_commit']).to eq(base_sha)
      expect(state['review_base_commit']).to eq(advanced_base_sha)
      expect(Autowork::GitRepo.new(repo).ancestor?('parent-task', 'HEAD')).to be(true)
    end

    it 'rebases onto a positional new base with an explicit task selector' do
      task_root, task_folder = make_env_task
      repo = make_git_repo
      add_origin_remote(repo)
      base_sha = commit_file(repo, 'base.txt', "base\n", 'base')
      system('git', '-C', repo, 'branch', '-M', 'master', out: File::NULL, err: File::NULL)
      system('git', '-C', repo, 'branch', 'parent-task', base_sha, out: File::NULL, err: File::NULL)
      system('git', '-C', repo, 'checkout', '-b', 'feature-without-task-id', 'parent-task', out: File::NULL, err: File::NULL)
      tmux = instance_double(Autowork::Tmux, discover_roles: role_panes(repo))

      stub_const('Autowork::TASK_ROOT', task_root)
      stub_const('Autowork::DOTS_REPO', repo)
      Autowork::RunSetup.new(%w[env 0003 parent-task], tmux: tmux).prepare!
      commit_file(repo, 'task.txt', "task\n", 'task work')
      system('git', '-C', repo, 'checkout', 'master', out: File::NULL, err: File::NULL)
      master_sha = commit_file(repo, 'master.txt', "master\n", 'advance master')
      system('git', '-C', repo, 'push', 'origin', 'master', out: File::NULL, err: File::NULL)
      system('git', '-C', repo, 'checkout', 'feature-without-task-id', out: File::NULL, err: File::NULL)

      Autowork::BaseRebaser.new(%w[master --task 0003], cwd: repo).run

      files = Autowork::RunFiles.new(task_folder)
      config = YAML.safe_load(File.read(files.config_path))
      state = Autowork::StateStore.new(files.state_path).read
      expect(config['original_review_base_ref']).to eq('parent-task')
      expect(config['original_review_base_commit']).to eq(base_sha)
      expect(config['review_base_ref']).to eq('origin/master')
      expect(config['review_base_commit']).to eq(master_sha)
      expect(state['original_review_base_ref']).to eq('parent-task')
      expect(state['review_base_ref']).to eq('origin/master')
      expect(Autowork::GitRepo.new(repo).ancestor?('origin/master', 'HEAD')).to be(true)
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

      expect { described_class.new(%w[env 0003], tmux: tmux).run }
        .to raise_error(Autowork::Error, /Worker status timeout/)

      state = state_store.read
      expect(state['status']).to eq('running')
      expect(state['phase']).to eq('waiting_for_final_super_review')
      expect(state.dig('steps', '1', 'status')).to eq('accepted')
      expect(File.read(files.final_checks_path)).to include('skipped')
      expect(tmux).to have_received(:send_prompt).with('%3', files.prompt_path('final_super_review1_request.md'))
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

    it 'records non-minor out-of-task findings as follow-ups without debate' do
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
      state['current_findings'] = [{ 'id' => 'B1', 'severity' => 'BLOCKER', 'title' => 'Future bug', 'body' => 'Outside task' }]
      state['review_iteration'] = 1
      state_store.write(state)
      File.write(files.resolution_path(1, 1), "B1 follow-up\n")
      File.write(files.status_path(1, 'pi', 'classify', 1), JSON.pretty_generate(
        'status' => 'done',
        'agent' => 'pi',
        'phase' => 'classify',
        'step' => 1,
        'summary' => 'recorded follow-up',
        'resolutions' => [
          { 'finding_id' => 'B1', 'decision' => 'follow_up', 'rationale' => 'valid but outside this task and not minor' }
        ]
      ))

      expect { described_class.new(%w[env 0003], tmux: tmux).run }
        .to raise_error(Autowork::Error, /Worker status timeout/)

      state = state_store.read
      expect(state['step_review_followups']).to include('B1: valid but outside this task and not minor')
      expect(state['phase']).to eq('waiting_for_final_super_review')
      expect(state.dig('steps', '1', 'status')).to eq('accepted')
      expect(tmux).to have_received(:send_prompt).with('%3', files.prompt_path('final_super_review1_request.md'))
    end

    it 'rejects MINOR findings recorded as follow-ups' do
      task_root, task_folder = make_env_task
      repo = make_git_repo
      tmux = instance_double(Autowork::Tmux, discover_roles: role_panes(repo))

      stub_const('Autowork::TASK_ROOT', task_root)
      stub_const('Autowork::DOTS_REPO', repo)
      Autowork::RunSetup.new(%w[env 0003], tmux: tmux).prepare!

      files = Autowork::RunFiles.new(task_folder)
      state_store = Autowork::StateStore.new(files.state_path)
      state = state_store.read
      state['phase'] = 'waiting_for_pi_classify'
      state['current_findings'] = [{ 'id' => 'M1', 'severity' => 'MINOR', 'title' => 'Small fix', 'body' => 'Fixable' }]
      state['review_iteration'] = 1
      state_store.write(state)
      File.write(files.resolution_path(1, 1), "M1 follow-up\n")
      File.write(files.status_path(1, 'pi', 'classify', 1), JSON.pretty_generate(
        'status' => 'done',
        'agent' => 'pi',
        'phase' => 'classify',
        'step' => 1,
        'summary' => 'recorded follow-up',
        'resolutions' => [
          { 'finding_id' => 'M1', 'decision' => 'follow_up', 'rationale' => 'minor but later' }
        ]
      ))

      expect { described_class.new(%w[env 0003], tmux: tmux).run }
        .to raise_error(Autowork::Error, /MINOR findings must be fixed now/)
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

      expect { described_class.new(%w[env 0003], tmux: tmux).run }
        .to raise_error(Autowork::Error, /Worker status timeout/)

      state = state_store.read
      expect(state['phase']).to eq('waiting_for_final_super_review')
      expect(state.dig('steps', '1', 'status')).to eq('accepted')
      expect(tmux).to have_received(:send_prompt).with('%3', files.prompt_path('final_super_review1_request.md'))
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

    it 'tells Claude step reviewers not to run test or lint commands' do
      task_root, task_folder = make_env_task
      repo = make_git_repo
      tmux = instance_double(Autowork::Tmux, discover_roles: role_panes(repo))

      stub_const('Autowork::TASK_ROOT', task_root)
      stub_const('Autowork::DOTS_REPO', repo)
      Autowork::RunSetup.new(%w[env 0003], tmux: tmux).prepare!

      files = Autowork::RunFiles.new(task_folder)
      prompt = Autowork::PromptWriter.new(files, Autowork::TaskResolver.new(%w[env 0003], cwd: repo).resolve, Autowork::GitRepo.new(repo)).claude_review(1, 1, 'a' * 40)
      text = File.read(prompt)

      expect(text).to include('Do not run RSpec, RuboCop, linters, formatters, or any other test/check command during normal step review')
      expect(text).to include('not full-suite and not targeted')
      expect(text).to include('`/autowork` runs full final checks after all planned steps are accepted')
    end

    it 'tells Claude final-check reviewers not to run test or lint commands' do
      task_root, task_folder = make_env_task
      repo = make_git_repo
      tmux = instance_double(Autowork::Tmux, discover_roles: role_panes(repo))

      stub_const('Autowork::TASK_ROOT', task_root)
      stub_const('Autowork::DOTS_REPO', repo)
      Autowork::RunSetup.new(%w[env 0003], tmux: tmux).prepare!

      files = Autowork::RunFiles.new(task_folder)
      prompt = Autowork::PromptWriter.new(files, Autowork::TaskResolver.new(%w[env 0003], cwd: repo).resolve, Autowork::GitRepo.new(repo)).claude_final_check_review(1, ['a' * 40])
      text = File.read(prompt)

      expect(text).to include('Do not run RSpec, RuboCop, linters, formatters, or any other test/check command here')
      expect(text).to include('not full-suite and not targeted')
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

    it 'keeps final-check stdout and stderr compact in state while writing full output to final_checks.md' do
      task_root, task_folder = make_env_task
      repo = make_git_repo
      tmux = instance_double(Autowork::Tmux, discover_roles: role_panes(repo))
      allow(tmux).to receive(:send_prompt)

      stub_const('Autowork::TASK_ROOT', task_root)
      stub_const('Autowork::DOTS_REPO', repo)
      Autowork::RunSetup.new(%w[env 0003], tmux: tmux).prepare!

      files = Autowork::RunFiles.new(task_folder)
      config = YAML.safe_load(File.read(files.config_path))
      config['final_check_commands'] = ["printf '%s\\n' full-stdout; printf '%s\\n' full-stderr >&2; exit 1"]
      File.write(files.config_path, config.to_yaml)
      state_store = Autowork::StateStore.new(files.state_path)
      state = state_store.read
      state['phase'] = 'ready_to_run_final_checks'
      state_store.write(state)

      expect { described_class.new(%w[env 0003], tmux: tmux).run }
        .to raise_error(Autowork::Error, /Worker status timeout/)

      state = state_store.read
      final_check = state.fetch('final_checks').first
      failure = state.fetch('final_check_failures').first
      expect(final_check).not_to have_key('stdout')
      expect(final_check).not_to have_key('stderr')
      expect(final_check['stdout_tail']).to include('full-stdout')
      expect(failure['stderr_tail']).to include('full-stderr')
      expect(File.read(files.final_checks_path)).to include('full-stdout', 'full-stderr')
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

      expect { described_class.new(%w[env 0003], tmux: tmux).run }
        .to raise_error(Autowork::Error, /Worker status timeout/)

      state = state_store.read
      expect(state['phase']).to eq('waiting_for_final_super_review')
      expect(state['final_check_fix_commits']).to be_nil
      expect(`git -C #{repo} log --oneline 2>/dev/null`.strip).to be_empty
      expect(File.read(files.final_checks_path)).to include('Status: passed')
      expect(tmux).to have_received(:send_prompt).with('%3', files.prompt_path('final_super_review1_request.md'))
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

      expect { described_class.new(%w[env 0003], tmux: tmux).run }
        .to raise_error(Autowork::Error, /Worker status timeout/)

      state = state_store.read
      expect(state['phase']).to eq('waiting_for_final_super_review')
      expect(state['final_check_reviewed']).to be(true)
      expect(tmux).to have_received(:send_prompt).with('%3', files.prompt_path('final_super_review1_request.md'))
    end

    it 'stops for manager-context review when final super-review reports no actionable findings' do
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
      state['phase'] = 'waiting_for_pi_final_review'
      state['final_pi_review_iteration'] = 1
      state['final_super_reviewed'] = true
      state['final_checks'] = [{ 'command' => nil, 'status' => 'skipped', 'summary' => 'none' }]
      state_store.write(state)
      FileUtils.rm_rf(File.join(files.log_dir, 'manager_reviews'))
      File.write(files.super_review_path, "# Super review\n\nDiff base: main\n")
      File.write(files.pi_final_review_path, "# Pi final review\n\nNo findings.\n")
      File.write(files.status_path(0, 'pi', 'final_review', 1), JSON.pretty_generate(
        'status' => 'done',
        'agent' => 'pi',
        'phase' => 'final_review',
        'step' => 0,
        'summary' => 'clean',
        'findings' => []
      ))

      described_class.new(%w[env 0003], tmux: tmux).run

      state = state_store.read
      expect(state['status']).to eq('manager_review')
      expect(state['phase']).to eq('ready_for_manager_final_review')
      expect(state['final_super_reviewed']).to eq(true)
      expect(File.directory?(File.join(files.log_dir, 'manager_reviews'))).to be(true)
      expect(File.read(files.manager_review_iteration_path(1))).to include('Review iteration: 1')
      final_summary = File.read(files.final_summary_path)
      expect(final_summary).to include('Final super-review')
      expect(final_summary).to include('pi-final-review.md')
      expect(final_summary).to include('Final status: manager_review')
      expect(final_summary).to include('## Unresolved caveats')
      expect(final_summary).to include('- None.')
      expect(final_summary).not_to include('unresolved disagreement after the configured round limit')
      expect(final_summary).to include('- Final outcome: accepted.')
      expect(File.read(files.manager_review_path)).to include('production-ready if the user does not perform another review')
    end

    it 'asks final super-review to emit report-only follow-ups in status JSON' do
      task_root, task_folder = make_env_task
      repo = make_git_repo
      tmux = instance_double(Autowork::Tmux, discover_roles: role_panes(repo))

      stub_const('Autowork::TASK_ROOT', task_root)
      stub_const('Autowork::DOTS_REPO', repo)
      Autowork::RunSetup.new(%w[env 0003], tmux: tmux).prepare!

      files = Autowork::RunFiles.new(task_folder)
      prompt = Autowork::PromptWriter.new(files, Autowork::TaskResolver.new(%w[env 0003], cwd: repo).resolve, Autowork::GitRepo.new(repo)).claude_final_super_review(1, 'main')
      text = File.read(prompt)

      expect(text).to include('"followups"')
      expect(text).to include('Put non-actionable report-only advisories')
    end

    it 'gives pi-worker the exact final review goal after Claude super-review' do
      task_root, task_folder = make_env_task
      repo = make_git_repo
      tmux = instance_double(Autowork::Tmux, discover_roles: role_panes(repo))

      stub_const('Autowork::TASK_ROOT', task_root)
      stub_const('Autowork::DOTS_REPO', repo)
      Autowork::RunSetup.new(%w[env 0003], tmux: tmux).prepare!

      files = Autowork::RunFiles.new(task_folder)
      prompt = Autowork::PromptWriter.new(files, Autowork::TaskResolver.new(%w[env 0003], cwd: repo).resolve, Autowork::GitRepo.new(repo)).pi_final_review(1, 'main')
      text = File.read(prompt)

      expect(text).to include('review all the changes and try to find issues, gaps, and improvement opportunities. But ignore very minor issues')
      expect(text).to include('"phase": "final_review"')
      expect(text).to include('entire final branch diff')
    end

    it 'sends Pi a super-review fix prompt when final super-review reports findings' do
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
      state['phase'] = 'waiting_for_final_super_review'
      state['final_super_review_iteration'] = 1
      state['final_checks'] = [{ 'command' => nil, 'status' => 'skipped', 'summary' => 'none' }]
      state_store.write(state)
      File.write(files.super_review_path, "# Super review\n\nDiff base: main\n")
      File.write(files.status_path(0, 'claude', 'super_review', 1), JSON.pretty_generate(
        'status' => 'done',
        'agent' => 'claude',
        'phase' => 'super_review',
        'step' => 0,
        'summary' => 'one finding',
        'findings' => [{ 'id' => 'SR1', 'severity' => 'BLOCKER', 'title' => 'Bug', 'body' => 'Broken', 'recommendation' => 'Fix' }],
        'followups' => ['Run a provider smoke test later']
      ))

      expect { described_class.new(%w[env 0003], tmux: tmux).run }
        .to raise_error(Autowork::Error, /Worker status timeout/)

      state = state_store.read
      expect(state['phase']).to eq('waiting_for_pi_super_review_fix')
      expect(state['final_super_review_findings'].first['id']).to eq('SR1')
      expect(state['final_super_review_followups']).to include('Run a provider smoke test later')
      expect(tmux).to have_received(:send_prompt).with('%2', files.prompt_path('super_review_pi_fix1_request.md'))
    end

    it 'routes Pi final-review findings to the manager gate without changing Claude findings' do
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
      state['phase'] = 'waiting_for_pi_final_review'
      state['final_pi_review_iteration'] = 1
      state['final_super_reviewed'] = true
      state['final_super_review_findings'] = [{ 'id' => 'SR1', 'severity' => 'BLOCKER', 'title' => 'Claude bug', 'body' => 'Broken', 'recommendation' => 'Fix Claude bug' }]
      state['final_checks'] = [{ 'command' => nil, 'status' => 'skipped', 'summary' => 'none' }]
      state_store.write(state)
      File.write(files.super_review_path, "# Super review\n")
      File.write(files.pi_final_review_path, "# Pi final review\n")
      File.write(files.status_path(0, 'pi', 'final_review', 1), JSON.pretty_generate(
        'status' => 'done',
        'agent' => 'pi',
        'phase' => 'final_review',
        'step' => 0,
        'summary' => 'one Pi finding',
        'findings' => [{ 'id' => 'P1', 'severity' => 'MINOR', 'title' => 'Pi gap', 'body' => 'Incomplete', 'recommendation' => 'Fix Pi gap' }]
      ))

      described_class.new(%w[env 0003], tmux: tmux).run

      state = state_store.read
      expect(state['phase']).to eq('ready_for_manager_final_review')
      expect(state['final_super_review_findings'].map { |finding| finding['id'] }).to eq(['SR1'])
      expect(state['final_pi_review_findings'].map { |finding| finding['id'] }).to eq(['P1'])
      expect(tmux).not_to have_received(:send_prompt).with('%2', files.prompt_path('super_review_pi_fix1_request.md'))
      expect(File.read(files.final_summary_path)).to include('pi-final-review.md')
    end

    it 'sends Pi super-review disagreements to Claude for scoped review without committing' do
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
      state['phase'] = 'waiting_for_pi_super_review_fix'
      state['super_review_fix_iteration'] = 1
      state['final_super_review_findings'] = [{ 'id' => 'SR1', 'severity' => 'BLOCKER', 'title' => 'Bug', 'body' => 'Broken' }]
      state_store.write(state)
      File.write(files.super_fix_result_path(1), "SR1 disputed\n")
      File.write(files.status_path(0, 'pi', 'super_fix', 1), JSON.pretty_generate(
        'status' => 'done',
        'agent' => 'pi',
        'phase' => 'super_fix',
        'step' => 0,
        'summary' => 'disputed SR1',
        'resolutions' => [{ 'finding_id' => 'SR1', 'decision' => 'dispute', 'rationale' => 'task explicitly excludes it' }],
        'checks_run' => [],
        'followups' => []
      ))

      expect { described_class.new(%w[env 0003], tmux: tmux).run }
        .to raise_error(Autowork::Error, /Worker status timeout/)

      state = state_store.read
      expect(state['phase']).to eq('waiting_for_claude_super_review_fix_review')
      expect(state['super_review_fix_commits']).to be_nil
      expect(`git -C #{repo} log --oneline 2>/dev/null`.strip).to be_empty
      expect(tmux).to have_received(:send_prompt).with('%3', files.prompt_path('super_review_claude_fix_review1_request.md'))
    end

    it 'commits a super-review fix, reruns final checks, and sends a scoped Claude review' do
      task_root, task_folder = make_env_task
      repo = make_git_repo
      tmux = instance_double(Autowork::Tmux, discover_roles: role_panes(repo))
      allow(tmux).to receive(:send_prompt)

      stub_const('Autowork::TASK_ROOT', task_root)
      stub_const('Autowork::DOTS_REPO', repo)
      Autowork::RunSetup.new(%w[env 0003], tmux: tmux).prepare!

      files = Autowork::RunFiles.new(task_folder)
      config = YAML.safe_load(File.read(files.config_path))
      config['final_check_commands'] = ['test -f super-fixed.txt']
      File.write(files.config_path, config.to_yaml)
      state_store = Autowork::StateStore.new(files.state_path)
      state = state_store.read
      state['phase'] = 'waiting_for_pi_super_review_fix'
      state['super_review_fix_iteration'] = 1
      state['final_super_review_findings'] = [{ 'id' => 'SR1', 'severity' => 'BLOCKER', 'title' => 'Bug', 'body' => 'Broken' }]
      state_store.write(state)
      File.write(files.super_fix_result_path(1), "Fixed SR1\n")
      File.write(files.status_path(0, 'pi', 'super_fix', 1), JSON.pretty_generate(
        'status' => 'done',
        'agent' => 'pi',
        'phase' => 'super_fix',
        'step' => 0,
        'summary' => 'fixed SR1',
        'resolutions' => [{ 'finding_id' => 'SR1', 'decision' => 'accept', 'rationale' => 'real bug' }],
        'checks_run' => [],
        'followups' => []
      ))
      File.write(File.join(repo, 'super-fixed.txt'), "fixed\n")

      expect { described_class.new(%w[env 0003], tmux: tmux).run }
        .to raise_error(Autowork::Error, /Worker status timeout/)

      state = state_store.read
      expect(`git -C #{repo} log -1 --pretty=%s`.strip).to eq('Super-review fix 1')
      expect(state['super_review_fix_commits'].first).to match(/\A[0-9a-f]{40}\z/)
      expect(state['phase']).to eq('waiting_for_claude_super_review_fix_review')
      expect(File.read(files.final_checks_path)).to include('Status: passed')
      expect(tmux).to have_received(:send_prompt).with('%3', files.prompt_path('super_review_claude_fix_review1_request.md'))
    end

    it 'starts Pi final review when Claude accepts the scoped super-review fix review' do
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
      state['phase'] = 'waiting_for_claude_super_review_fix_review'
      state['super_review_fix_iteration'] = 1
      state['super_review_fix_commits'] = ['a' * 40]
      state['pending_super_review_fix_review'] = true
      state['final_checks'] = [{ 'command' => 'true', 'status' => 'passed', 'exit_status' => 0, 'stdout' => '', 'stderr' => '' }]
      state['final_super_review_followups'] = ['Run a provider smoke test later']
      state_store.write(state)
      File.write(files.super_fix_review_path(1), "Scoped review clean\n")
      File.write(files.status_path(0, 'claude', 'super_fix_review', 1), JSON.pretty_generate(
        'status' => 'done',
        'agent' => 'claude',
        'phase' => 'super_fix_review',
        'step' => 0,
        'summary' => 'accepted',
        'findings' => []
      ))

      expect { described_class.new(%w[env 0003], tmux: tmux).run }
        .to raise_error(Autowork::Error, /Worker status timeout/)

      state = state_store.read
      expect(state['final_super_reviewed']).to eq(true)
      expect(state['phase']).to eq('waiting_for_pi_final_review')
      expect(tmux).to have_received(:send_prompt).with('%2', files.prompt_path('final_pi_review1_request.md'))
    end

    it 'commits a manager fix, reruns final checks, and sends a scoped Claude review' do
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
      state['phase'] = 'waiting_for_pi_manager_fix'
      state['manager_review_iteration'] = 1
      state['manager_fix_iteration'] = 1
      state['manager_review_findings'] = [{ 'id' => 'MR1', 'severity' => 'BLOCKER', 'title' => 'Bug', 'body' => 'Broken', 'recommendation' => 'Fix it' }]
      state_store.write(state)
      File.write(files.manager_fix_result_path(1), "Fixed MR1\n")
      File.write(files.status_path(0, 'pi', 'manager_fix', 1), JSON.pretty_generate(
        'status' => 'done',
        'agent' => 'pi',
        'phase' => 'manager_fix',
        'step' => 0,
        'summary' => 'fixed manager finding',
        'checks_run' => [],
        'followups' => []
      ))
      File.write(File.join(repo, 'manager-fixed.txt'), "fixed\n")

      expect { described_class.new(%w[env 0003], tmux: tmux).run }
        .to raise_error(Autowork::Error, /Worker status timeout/)

      state = state_store.read
      expect(`git -C #{repo} log -1 --pretty=%s`.strip).to eq('Manager review fix 1')
      expect(state['manager_fix_commits'].first).to match(/\A[0-9a-f]{40}\z/)
      expect(state['phase']).to eq('waiting_for_claude_manager_fix_review')
      expect(File.read(files.final_checks_path)).to include('Status: passed')
      expect(tmux).to have_received(:send_prompt).with('%3', files.prompt_path('manager_review_claude_fix_review1_request.md'))
    end

    it 'returns to a fresh manager gate when Claude accepts a manager fix' do
      task_root, task_folder = make_env_task
      repo = make_git_repo
      fix_sha = commit_file(repo, 'manager-fixed.txt', "fixed\n", 'Manager review fix 1')
      tmux = instance_double(Autowork::Tmux, discover_roles: role_panes(repo))

      stub_const('Autowork::TASK_ROOT', task_root)
      stub_const('Autowork::DOTS_REPO', repo)
      Autowork::RunSetup.new(%w[env 0003], tmux: tmux).prepare!

      files = Autowork::RunFiles.new(task_folder)
      state_store = Autowork::StateStore.new(files.state_path)
      state = state_store.read
      state['phase'] = 'waiting_for_claude_manager_fix_review'
      state['manager_review_iteration'] = 1
      state['manager_fix_iteration'] = 1
      state['manager_fix_commits'] = [fix_sha]
      state['pending_manager_fix_review'] = true
      state['manager_review_findings'] = [{ 'id' => 'MR1', 'severity' => 'BLOCKER', 'title' => 'Bug', 'body' => 'Broken', 'recommendation' => 'Fix it' }]
      state['manager_review_cycles'] = [{ 'iteration' => 1, 'status' => 'routed_for_fix', 'summary' => 'one bug', 'findings_count' => 1 }]
      state['final_checks'] = [{ 'command' => 'true', 'status' => 'passed', 'exit_status' => 0 }]
      state_store.write(state)
      File.write(files.manager_review_iteration_path(1), "Review iteration: 1\n")
      File.write(files.manager_fix_review_path(1), "Manager fix accepted\n")
      File.write(files.status_path(0, 'claude', 'manager_fix_review', 1), JSON.pretty_generate(
        'status' => 'done',
        'agent' => 'claude',
        'phase' => 'manager_fix_review',
        'step' => 0,
        'summary' => '0 BLOCKER / 0 MINOR. Accept.',
        'findings' => []
      ))

      described_class.new(%w[env 0003], tmux: tmux).run

      state = state_store.read
      expect(state['phase']).to eq('ready_for_manager_final_review')
      expect(state['manager_review_iteration']).to eq(2)
      expect(state['manager_review_cycles'].first['status']).to eq('fixed_and_reviewed')
      expect(File.read(files.final_summary_path)).to include('Manager review fix 1', 'Manager review fix review 1')
      expect(File.read(files.manager_review_path)).to include('manager_review2_findings.json')
      expect(File.read(files.manager_review_iteration_path(1))).to include('Review iteration: 1')
      expect(File.read(files.manager_review_iteration_path(2))).to include('Review iteration: 2')
    end

    it 'routes Claude manager-fix findings into the next Pi manager fix iteration' do
      task_root, task_folder = make_env_task
      repo = make_git_repo
      fix_sha = commit_file(repo, 'manager-fixed.txt', "incomplete\n", 'Manager review fix 1')
      tmux = instance_double(Autowork::Tmux, discover_roles: role_panes(repo))
      allow(tmux).to receive(:send_prompt)

      stub_const('Autowork::TASK_ROOT', task_root)
      stub_const('Autowork::DOTS_REPO', repo)
      Autowork::RunSetup.new(%w[env 0003], tmux: tmux).prepare!

      files = Autowork::RunFiles.new(task_folder)
      state_store = Autowork::StateStore.new(files.state_path)
      state = state_store.read
      state['phase'] = 'waiting_for_claude_manager_fix_review'
      state['manager_review_iteration'] = 1
      state['manager_fix_iteration'] = 1
      state['manager_fix_commits'] = [fix_sha]
      state['pending_manager_fix_review'] = true
      state['manager_review_findings'] = [{ 'id' => 'MR1', 'severity' => 'BLOCKER', 'title' => 'Bug', 'body' => 'Broken', 'recommendation' => 'Fix it' }]
      state['final_checks'] = [{ 'command' => 'true', 'status' => 'passed', 'exit_status' => 0 }]
      state_store.write(state)
      File.write(files.manager_fix_review_path(1), "One issue remains\n")
      File.write(files.status_path(0, 'claude', 'manager_fix_review', 1), JSON.pretty_generate(
        'status' => 'done',
        'agent' => 'claude',
        'phase' => 'manager_fix_review',
        'step' => 0,
        'summary' => '0 BLOCKER / 1 MINOR',
        'findings' => [{ 'id' => 'MRF1', 'severity' => 'MINOR', 'title' => 'Missing regression', 'body' => 'Edge case remains', 'recommendation' => 'Add coverage' }]
      ))

      expect { described_class.new(%w[env 0003], tmux: tmux).run }
        .to raise_error(Autowork::Error, /Worker status timeout/)

      state = state_store.read
      expect(state['phase']).to eq('waiting_for_pi_manager_fix')
      expect(state['manager_fix_iteration']).to eq(2)
      expect(state['manager_fix_review_findings'].first['id']).to eq('MRF1')
      expect(tmux).to have_received(:send_prompt).with('%2', files.prompt_path('manager_review_pi_fix2_request.md'))
      expect(File.read(files.prompt_path('manager_review_pi_fix2_request.md'))).to include('Missing regression')
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

  describe Autowork::ManagerReviewFix do
    around do |example|
      previous = ENV['AUTOWORK_WORKER_STATUS_TIMEOUT_SECONDS']
      ENV['AUTOWORK_WORKER_STATUS_TIMEOUT_SECONDS'] = '0'
      example.run
    ensure
      ENV['AUTOWORK_WORKER_STATUS_TIMEOUT_SECONDS'] = previous
    end

    it 'validates structured findings and starts the automated Pi manager-fix loop' do
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
      state['status'] = 'manager_review'
      state['phase'] = 'ready_for_manager_final_review'
      state['manager_review_iteration'] = 1
      state_store.write(state)
      File.write(files.manager_review_path, "# Manager review\n\n- Pending.\n")
      File.write(files.manager_findings_path(1), JSON.pretty_generate(
        'summary' => 'Manager context found one production bug',
        'findings' => [{
          'id' => 'MR1',
          'severity' => 'BLOCKER',
          'title' => 'Wrong campaign attribution',
          'body' => 'Account state is not a campaign event',
          'recommendation' => 'Use campaign-scoped state'
        }],
        'followups' => ['Run a provider smoke test after deploy']
      ))
      File.write(files.lock_path, JSON.pretty_generate('pid' => 999_999_999))

      expect { described_class.new([task_folder], tmux: tmux).run }
        .to raise_error(Autowork::Error, /Worker status timeout/)

      state = state_store.read
      expect(state['phase']).to eq('waiting_for_pi_manager_fix')
      expect(state['manager_review_findings'].first['id']).to eq('MR1')
      expect(state['manager_review_followups']).to include('Run a provider smoke test after deploy')
      expect(state['manager_review_cycles'].first).to include('iteration' => 1, 'status' => 'routed_for_fix', 'findings_count' => 1)
      expect(tmux).to have_received(:send_prompt).with('%2', files.prompt_path('manager_review_pi_fix1_request.md'))
      expect(File.read(files.manager_review_path)).to include('findings routed automatically')
      expect(File.file?(files.lock_path)).to eq(false)
    end

    it 'rejects manager findings while an autowork process owns the run lock' do
      task_root, task_folder = make_env_task
      repo = make_git_repo
      tmux = instance_double(Autowork::Tmux, discover_roles: role_panes(repo))

      stub_const('Autowork::TASK_ROOT', task_root)
      stub_const('Autowork::DOTS_REPO', repo)
      Autowork::RunSetup.new(%w[env 0003], tmux: tmux).prepare!

      files = Autowork::RunFiles.new(task_folder)
      File.write(files.lock_path, JSON.pretty_generate('pid' => Process.pid))

      expect { described_class.new([task_folder], tmux: tmux).run }
        .to raise_error(Autowork::Error, /already locked by live pid/)
    end

    it 'rejects invalid manager findings before sending a worker prompt' do
      task_root, task_folder = make_env_task
      repo = make_git_repo
      tmux = instance_double(Autowork::Tmux, discover_roles: role_panes(repo))

      stub_const('Autowork::TASK_ROOT', task_root)
      stub_const('Autowork::DOTS_REPO', repo)
      Autowork::RunSetup.new(%w[env 0003], tmux: tmux).prepare!

      files = Autowork::RunFiles.new(task_folder)
      state_store = Autowork::StateStore.new(files.state_path)
      state = state_store.read
      state['phase'] = 'ready_for_manager_final_review'
      state['manager_review_iteration'] = 1
      state_store.write(state)
      File.write(files.manager_findings_path(1), JSON.pretty_generate('summary' => 'bad', 'findings' => []))

      expect { described_class.new([task_folder], tmux: tmux).run }
        .to raise_error(Autowork::Error, /findings must be a non-empty array/)
    end
  end

  describe Autowork::ManagerReviewPass do
    it 'marks a pending manager-context review as complete' do
      task_root, task_folder = make_env_task
      repo = make_git_repo
      tmux = instance_double(Autowork::Tmux, discover_roles: role_panes(repo))

      stub_const('Autowork::TASK_ROOT', task_root)
      stub_const('Autowork::DOTS_REPO', repo)
      Autowork::RunSetup.new(%w[env 0003], tmux: tmux).prepare!

      files = Autowork::RunFiles.new(task_folder)
      state_store = Autowork::StateStore.new(files.state_path)
      state = state_store.read
      state['status'] = 'manager_review'
      state['phase'] = 'ready_for_manager_final_review'
      state['next_action'] = 'manager_context_production_readiness_review'
      state_store.write(state)
      File.write(files.final_summary_path, "# Summary\n\n- Final status: manager_review\n- Final phase: ready_for_manager_final_review\n\n## Manager review loop\n\n- Awaiting manager review iteration 1.\n")
      File.write(files.manager_review_path, "# Manager-context production-readiness review\n\n## Manager review result\n\n- Pending.\n")

      described_class.new([task_folder]).run

      state = state_store.read
      expect(state['status']).to eq('done')
      expect(state['phase']).to eq('complete')
      expect(state['manager_context_reviewed']).to eq(true)
      expect(File.read(files.final_summary_path)).to include('Final status: done')
      expect(File.read(files.final_summary_path)).to include('- Review 1: passed.')
      expect(File.read(files.final_summary_path)).to include('Manager-context production-readiness review')
      expect(File.read(files.manager_review_path)).to include('production-ready if the user does not perform another review')
    end

    it 'rejects a pass from a different branch' do
      task_root, task_folder = make_env_task
      repo = make_git_repo
      tmux = instance_double(Autowork::Tmux, discover_roles: role_panes(repo))

      stub_const('Autowork::TASK_ROOT', task_root)
      stub_const('Autowork::DOTS_REPO', repo)
      Autowork::RunSetup.new(%w[env 0003], tmux: tmux).prepare!
      system('git', '-C', repo, 'switch', '-c', 'unrelated', out: File::NULL, err: File::NULL)

      expect { described_class.new([task_folder]).run }
        .to raise_error(Autowork::Error, /Manager review belongs to branch/)
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
