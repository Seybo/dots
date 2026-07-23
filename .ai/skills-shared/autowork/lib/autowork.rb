# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'open3'
require 'time'
require 'yaml'

module Autowork
  class Error < StandardError; end

  ROOT = File.expand_path('..', __dir__)
  TASK_ROOT = '/Volumes/dev/_tasks'
  DOTS_REPO = '/Users/inseybo/.dots'
  PROJECTS_FILE = File.expand_path('../components/projects.yml', ROOT)
  STEP_HEADING = /^## Step ([0-9]+)\b/.freeze
  MANAGER_REVIEW_SEVERITIES = %w[BLOCKER MINOR].freeze
  DEFAULT_MAX_TOTAL_COMMITS = 15

  class Shell
    Result = Struct.new(:stdout, :stderr, :status, keyword_init: true) do
      def success?
        status.success?
      end
    end

    def self.capture(*args, chdir: nil)
      options = {}
      options[:chdir] = chdir if chdir
      stdout, stderr, status = Open3.capture3(*args, **options)
      Result.new(stdout: stdout, stderr: stderr, status: status)
    end

    def self.capture!(*args, chdir: nil)
      result = capture(*args, chdir: chdir)
      return result.stdout if result.success?

      raise Error, "Command failed: #{args.join(' ')}\n#{result.stderr}"
    end
  end

  TaskContext = Struct.new(:project, :task_id, :task_root, :task_folder, :code_dir, :review_base_ref, keyword_init: true)
  Pane = Struct.new(:id, :session, :window_id, :window_name, :active, :command, :title, :path, keyword_init: true)

  class ProjectRegistry
    ORDINAL_PATTERN = /\A(\d+)(st|nd|rd|th)\z/.freeze

    def initialize(path)
      data = YAML.safe_load(File.read(path), permitted_classes: [], aliases: false)
      @projects = data.fetch('projects').transform_keys(&:to_s)
    rescue Errno::ENOENT, Psych::Exception => e
      raise Error, "Invalid project registry #{path}: #{e.message}"
    end

    def session_alias?(value)
      !alias_parts(value).nil?
    end

    def normalize_alias(value)
      parts = alias_parts(value)
      return [value, nil] unless parts

      project, number = parts
      [project, ordinal(number)]
    end

    def project_and_workspace_for_path(path)
      candidates = @projects.filter_map do |project, config|
        root = checkout_root(config)
        next unless path == root || path.start_with?("#{root}/")

        [project, config, root]
      end
      project, config, root = candidates.max_by { |_, _, candidate_root| candidate_root.length }
      return unless project
      return [project, nil] if config['is_infrastructure'] || direct_checkout?(config)

      relative_path = path.delete_prefix("#{root}/")
      workspace = relative_path.split('/').first
      return [project, workspace] if canonical_ordinal?(workspace)

      [project, nil]
    end

    def code_dir(project, workspace)
      config = @projects.fetch(project) { raise Error, "Project is not registered: #{project}" }
      root = checkout_root(config)
      return root if config['is_infrastructure'] || direct_checkout?(config)
      raise Error, "#{project} workspace is ambiguous; pass #{project}<number>, such as #{project}1 or #{project}28" unless workspace

      File.join(root, workspace)
    end

    def session_alias(project, workspace)
      config = @projects.fetch(project)
      return project if config.fetch('is_infrastructure', false) || direct_checkout?(config)

      number = workspace.to_s[/\A\d+/]
      raise Error, "Cannot infer #{project} session alias from workspace #{workspace.inspect}" unless number

      "#{project}#{number}"
    end

    private

    def alias_parts(value)
      @projects.keys.sort_by { |project| -project.length }.each do |project|
        config = @projects.fetch(project)
        next if direct_checkout?(config) || config['is_infrastructure']

        match = value.match(/\A#{Regexp.escape(project)}(\d+)\z/)
        return [project, match[1]] if match && positive_number?(match[1])
      end
      nil
    end

    def checkout_root(config)
      direct_checkout?(config) ? config.fetch('checkout_path') : config.fetch('code_root')
    end

    def direct_checkout?(config)
      config['checkout_layout'] == 'direct'
    end

    def canonical_ordinal?(value)
      match = value.to_s.match(ORDINAL_PATTERN)
      match && ordinal(match[1]) == value
    end

    def positive_number?(value)
      value.to_i.positive?
    end

    def ordinal(number)
      number = number.to_i
      raise Error, 'Workspace number must be positive' unless number.positive?

      suffix = if (11..13).cover?(number % 100)
        'th'
      else
        { 1 => 'st', 2 => 'nd', 3 => 'rd' }.fetch(number % 10, 'th')
      end
      "#{number}#{suffix}"
    end
  end
  RolePanes = Struct.new(:manager, :pi_worker, :claude_worker, keyword_init: true)

  class TaskResolver
    def initialize(argv, cwd: Dir.pwd, projects_file: PROJECTS_FILE)
      @argv = argv.dup
      @cwd = File.expand_path(cwd)
      @registry = ProjectRegistry.new(projects_file)
    end

    def resolve
      project_arg, task_id, review_base_ref = parse_args
      project, checkout = project_arg ? normalize_project(project_arg) : infer_project
      task_root = File.join(TASK_ROOT, project)
      raise Error, "Task project not found: #{task_root}" unless File.directory?(task_root)

      code_dir = code_dir_for(project, checkout)
      task_id ||= infer_story_id(code_dir)
      raise Error, 'Could not infer task id. Pass /autowork <task_id> or /autowork <project> <task_id>.' if task_id.nil? || task_id.empty?
      raise Error, "Task id must be digits only, got #{task_id.inspect}" unless task_id.match?(/\A\d+\z/)

      task_folder = resolve_task_folder(task_root, task_id)
      TaskContext.new(project: project, task_id: task_id, task_root: task_root, task_folder: task_folder, code_dir: code_dir, review_base_ref: review_base_ref)
    end

    private

    def parse_args
      case @argv.length
      when 0 then [nil, nil, nil]
      when 1
        token = @argv[0]
        project_name?(token) || @registry.session_alias?(token) ? [token, nil, nil] : [nil, token, nil]
      when 2
        if project_name?(@argv[0]) || @registry.session_alias?(@argv[0])
          [@argv[0], @argv[1], nil]
        else
          [nil, @argv[0], @argv[1]]
        end
      when 3
        raise Error, 'Usage: autowork [project-or-session] [task_id] [full-base-branch-or-ref]' unless project_name?(@argv[0]) || @registry.session_alias?(@argv[0])

        [@argv[0], @argv[1], @argv[2]]
      else raise Error, 'Usage: autowork [project-or-session] [task_id] [full-base-branch-or-ref]'
      end
    end

    def project_name?(value)
      File.directory?(File.join(TASK_ROOT, value))
    end

    def normalize_project(value)
      @registry.normalize_alias(value)
    end

    def infer_project
      return ['env', nil] if @cwd == DOTS_REPO || @cwd.start_with?("#{DOTS_REPO}/")

      inferred = @registry.project_and_workspace_for_path(@cwd)
      return inferred if inferred

      raise Error, "Could not infer project from #{@cwd}. Pass project explicitly."
    end

    def code_dir_for(project, checkout)
      return DOTS_REPO if project == 'env'

      selected = checkout || @registry.project_and_workspace_for_path(@cwd)&.last
      @registry.code_dir(project, selected)
    end

    def infer_story_id(code_dir)
      return nil unless File.directory?(code_dir)

      branch = Shell.capture('git', '-C', code_dir, 'branch', '--show-current').stdout.strip
      match = branch.match(%r{(?:^|/)sc-(\d+)(?:/|$)})
      match && match[1]
    end

    def resolve_task_folder(task_root, task_id)
      exact = File.join(task_root, task_id)
      return exact if File.directory?(exact)

      matches = Dir.glob(File.join(task_root, "#{task_id}*")).select { |path| File.directory?(path) }
      raise Error, "No task folder starts with #{task_id.inspect} under #{task_root}" if matches.empty?
      raise Error, "Multiple task folders match #{task_id.inspect}:\n#{matches.join("\n")}" if matches.length > 1

      matches.first
    end
  end

  class GitRepo
    attr_reader :root

    def initialize(path)
      @root = File.realpath(Shell.capture!('git', '-C', path, 'rev-parse', '--show-toplevel').strip)
    end

    def clean?
      status.empty?
    end

    def status
      Shell.capture!('git', '-C', root, 'status', '--porcelain')
    end

    def branch
      Shell.capture!('git', '-C', root, 'branch', '--show-current').strip
    end

    def head_sha
      Shell.capture!('git', '-C', root, 'rev-parse', 'HEAD').strip
    end

    def head_sha_if_exists
      ref_exists?('HEAD') ? head_sha : nil
    end

    def add_all
      Shell.capture!('git', '-C', root, 'add', '-A')
    end

    def commit(message)
      Shell.capture!('git', '-C', root, 'commit', '-m', message)
      head_sha
    end

    def ref_exists?(ref)
      Shell.capture('git', '-C', root, 'rev-parse', '--verify', '--quiet', ref).success?
    end

    def ref_commit(ref)
      Shell.capture!('git', '-C', root, 'rev-parse', '--verify', "#{ref}^{commit}").strip
    end

    def ancestor?(ancestor_ref, descendant_ref)
      Shell.capture('git', '-C', root, 'merge-base', '--is-ancestor', ancestor_ref, descendant_ref).success?
    end

    def fetch_origin
      Shell.capture!('git', '-C', root, 'fetch', 'origin')
    end

    def rebase_onto(new_base_ref, old_base_commit)
      Shell.capture('git', '-C', root, 'rebase', '--onto', new_base_ref, old_base_commit)
    end

    def unmerged_files
      Shell.capture!('git', '-C', root, 'diff', '--name-only', '--diff-filter=U').lines.map(&:strip).reject(&:empty?)
    end
  end

  class StatusValidator
    ALLOWED_STATUSES = %w[done needs_user failed].freeze
    ALLOWED_AGENTS = %w[pi claude].freeze
    ALLOWED_PHASES = %w[implement review classify fix debate final_checks super_review super_fix super_fix_review manager_fix manager_fix_review].freeze

    Result = Struct.new(:valid, :errors, :data, keyword_init: true) do
      def valid?
        valid
      end
    end

    def validate_file(path, expected: {})
      data = JSON.parse(File.read(path))
      validate_hash(data, expected: expected)
    rescue Errno::ENOENT
      Result.new(valid: false, errors: ["missing status file: #{path}"], data: nil)
    rescue JSON::ParserError => e
      Result.new(valid: false, errors: ["invalid JSON: #{e.message}"], data: nil)
    end

    def validate_hash(data, expected: {})
      return Result.new(valid: false, errors: ['status JSON must be an object'], data: data) unless data.is_a?(Hash)

      errors = []
      validate_required_string(data, 'status', errors)
      validate_required_string(data, 'agent', errors)
      validate_required_string(data, 'phase', errors)
      validate_required_string(data, 'summary', errors)
      validate_step(data, errors)
      validate_membership(data, errors)
      validate_expected(data, expected, errors)
      validate_optional_fields(data, errors)
      validate_findings(data, errors)
      validate_resolutions(data, errors)
      validate_debate(data, errors)
      Result.new(valid: errors.empty?, errors: errors, data: data)
    end

    private

    def validate_required_string(data, key, errors)
      errors << "#{key} is required" unless data.key?(key)
      return unless data.key?(key)

      errors << "#{key} must be a non-empty string" unless data[key].is_a?(String) && !data[key].strip.empty?
    end

    def validate_step(data, errors)
      errors << 'step is required' unless data.key?('step')
      return unless data.key?('step')

      errors << 'step must be an integer' unless data['step'].is_a?(Integer)
    end

    def validate_membership(data, errors)
      errors << "status must be one of #{ALLOWED_STATUSES.join(', ')}" if data['status'].is_a?(String) && !ALLOWED_STATUSES.include?(data['status'])
      errors << "agent must be one of #{ALLOWED_AGENTS.join(', ')}" if data['agent'].is_a?(String) && !ALLOWED_AGENTS.include?(data['agent'])
      errors << "phase must be one of #{ALLOWED_PHASES.join(', ')}" if data['phase'].is_a?(String) && !ALLOWED_PHASES.include?(data['phase'])
    end

    def validate_expected(data, expected, errors)
      expected.each do |key, value|
        string_key = key.to_s
        errors << "#{string_key} expected #{value.inspect}, got #{data[string_key].inspect}" unless data[string_key] == value
      end
    end

    def validate_optional_fields(data, errors)
      errors << 'question is required when status is needs_user' if data['status'] == 'needs_user' && (!data['question'].is_a?(String) || data['question'].strip.empty?)
      errors << 'checks_run must be an array when present' if data.key?('checks_run') && !data['checks_run'].is_a?(Array)
    end

    def validate_findings(data, errors)
      if data['phase'] == 'manager_fix_review' && data['status'] == 'done' && !data.key?('findings')
        errors << 'findings is required for completed manager_fix_review'
        return
      end
      return unless data.key?('findings')

      unless data['findings'].is_a?(Array)
        errors << 'findings must be an array when present'
        return
      end
      data['findings'].each_with_index do |finding, index|
        unless finding.is_a?(Hash)
          errors << "findings[#{index}] must be an object"
          next
        end
        %w[id severity title body].each do |key|
          errors << "findings[#{index}].#{key} must be a non-empty string" unless finding[key].is_a?(String) && !finding[key].strip.empty?
        end
        allowed_severities = data['phase'] == 'manager_fix_review' ? MANAGER_REVIEW_SEVERITIES : %w[BLOCKER MINOR PASS CRITICAL HIGH MEDIUM]
        unless allowed_severities.include?(finding['severity'])
          errors << "findings[#{index}].severity must be one of #{allowed_severities.join(', ')}"
        end
      end
    end

    def validate_resolutions(data, errors)
      return unless data.key?('resolutions')

      unless data['resolutions'].is_a?(Array)
        errors << 'resolutions must be an array when present'
        return
      end
      data['resolutions'].each_with_index do |resolution, index|
        unless resolution.is_a?(Hash)
          errors << "resolutions[#{index}] must be an object"
          next
        end
        %w[finding_id decision rationale].each do |key|
          errors << "resolutions[#{index}].#{key} must be a non-empty string" unless resolution[key].is_a?(String) && !resolution[key].strip.empty?
        end
        allowed_decisions = data['phase'] == 'super_fix' ? %w[accept accept_with_alternative_fix dispute skip already_fixed out_of_scope follow_up needs_user] : %w[accept accept_with_alternative_fix dispute follow_up needs_user]
        unless allowed_decisions.include?(resolution['decision'])
          errors << "resolutions[#{index}].decision is invalid"
        end
      end
    end

    def validate_debate(data, errors)
      return unless data.key?('debate')

      debate = data['debate']
      unless debate.is_a?(Hash)
        errors << 'debate must be an object when present'
        return
      end
      %w[finding_id decision].each do |key|
        errors << "debate.#{key} must be a non-empty string" unless debate[key].is_a?(String) && !debate[key].strip.empty?
      end
      errors << 'debate.round must be an integer' unless debate['round'].is_a?(Integer)
      unless %w[agree_with_pi still_disagree accept accept_with_alternative_fix needs_user].include?(debate['decision'])
        errors << 'debate.decision is invalid'
      end
    end
  end

  class ManagerFindingsValidator
    ALLOWED_SEVERITIES = MANAGER_REVIEW_SEVERITIES

    Result = Struct.new(:valid, :errors, :data, keyword_init: true) do
      def valid?
        valid
      end
    end

    def validate_file(path)
      data = JSON.parse(File.read(path))
      validate_hash(data)
    rescue Errno::ENOENT
      Result.new(valid: false, errors: ["missing manager findings file: #{path}"], data: nil)
    rescue JSON::ParserError => e
      Result.new(valid: false, errors: ["invalid JSON: #{e.message}"], data: nil)
    end

    def validate_hash(data)
      errors = []
      unless data.is_a?(Hash)
        return Result.new(valid: false, errors: ['manager findings JSON must be an object'], data: data)
      end

      errors << 'summary must be a non-empty string' unless data['summary'].is_a?(String) && !data['summary'].strip.empty?
      findings = data['findings']
      if !findings.is_a?(Array) || findings.empty?
        errors << 'findings must be a non-empty array'
      else
        findings.each_with_index { |finding, index| validate_finding(finding, index, errors) }
      end
      errors << 'followups must be an array when present' if data.key?('followups') && !data['followups'].is_a?(Array)
      Result.new(valid: errors.empty?, errors: errors, data: data)
    end

    private

    def validate_finding(finding, index, errors)
      unless finding.is_a?(Hash)
        errors << "findings[#{index}] must be an object"
        return
      end

      %w[id severity title body recommendation].each do |key|
        errors << "findings[#{index}].#{key} must be a non-empty string" unless finding[key].is_a?(String) && !finding[key].strip.empty?
      end
      return if ALLOWED_SEVERITIES.include?(finding['severity'])

      errors << "findings[#{index}].severity must be one of #{ALLOWED_SEVERITIES.join(', ')}"
    end
  end

  class Tmux
    DEFAULT_SUBMIT_DELAY_SECONDS = 0.2

    def current_window_target
      Shell.capture!('tmux', 'display-message', '-p', '#{session_name}:#{window_id}').strip
    end

    def panes
      output = Shell.capture!('tmux', 'list-panes', '-t', current_window_target, '-F', pane_format)
      output.lines.filter_map do |line|
        id, session, window_id, window_name, active, command, title, path = line.chomp.split("\t", 8)
        Pane.new(id: id, session: session, window_id: window_id, window_name: window_name, active: active == '1', command: command, title: title, path: path)
      end
    end

    def discover_roles(repo_root)
      role_panes = panes
      roles = RolePanes.new(
        manager: select_title(role_panes, 'pi-manager'),
        pi_worker: select_title(role_panes, 'pi-worker'),
        claude_worker: select_title(role_panes, 'claude-worker')
      )
      verify_repo_roots!(roles, repo_root)
      roles
    end

    def pane_exists?(pane_id)
      Shell.capture('tmux', 'list-panes', '-a', '-F', '#{pane_id}').stdout.lines.map(&:strip).include?(pane_id)
    end

    def send_prompt(target, prompt_file)
      send_text(target, "Please read and follow: #{prompt_file}")
    end

    def send_text(target, text)
      Shell.capture!('tmux', 'send-keys', '-t', target, '-l', text)
      sleep submit_delay_seconds
      Shell.capture!('tmux', 'send-keys', '-t', target, 'Enter')
    end

    private

    def submit_delay_seconds
      ENV.fetch('AUTOWORK_SEND_SUBMIT_DELAY_SECONDS', DEFAULT_SUBMIT_DELAY_SECONDS).to_f
    end

    def pane_format
      ['#{pane_id}', '#{session_name}', '#{window_id}', '#{window_name}', '#{pane_active}', '#{pane_current_command}', '#{pane_title}', '#{pane_current_path}'].join("\t")
    end

    def select_title(panes, title)
      matching = panes.select { |pane| pane.title == title }
      raise Error, "No tmux pane titled #{title.inspect} in current window" if matching.empty?
      raise Error, "Multiple tmux panes titled #{title.inspect} in current window" if matching.length > 1

      matching.first
    end

    def verify_repo_roots!(roles, repo_root)
      expected_root = File.realpath(repo_root)
      roles.to_h.each_value do |pane|
        pane_root = GitRepo.new(pane.path).root
        raise Error, "Pane #{pane.id} git root #{pane_root} does not match repo root #{expected_root}" unless pane_root == expected_root
      end
    end
  end

  class Steps
    attr_reader :path, :numbers

    def initialize(path)
      @path = path
      @numbers = parse_numbers
    end

    def count = numbers.count

    private

    def parse_numbers
      raise Error, "Missing required steps file: #{path}. Run `/workit <project-or-task> create-steps-only` or invoke `/autowork` through the skill preflight so it can create the plan before starting the helper." unless File.file?(path)

      found = File.readlines(path).filter_map do |line|
        match = line.match(STEP_HEADING)
        match && match[1].to_i
      end
      raise Error, "#{path} has no headings matching #{STEP_HEADING.inspect}" if found.empty?

      found
    end
  end

  class RunFiles
    attr_reader :task_folder, :log_dir

    def initialize(task_folder)
      @task_folder = task_folder
      @log_dir = File.join(task_folder, 'autowork-log')
    end

    def mkdirs
      %w[control prompts reviews debates resolutions super_fixes manager_reviews manager_fixes status].each { |name| FileUtils.mkdir_p(File.join(log_dir, name)) }
    end

    def config_path = File.join(log_dir, 'config.yml')
    def state_path = File.join(log_dir, 'state.json')
    def lock_path = File.join(log_dir, 'run.lock')
    def pause_path = File.join(log_dir, 'control', 'pause')
    def paused_reason_path = File.join(log_dir, 'paused_reason.md')
    def rebase_conflicts_path = File.join(log_dir, 'rebase_conflicts.md')
    def final_checks_path = File.join(log_dir, 'final_checks.md')
    def final_summary_path = File.join(log_dir, 'final_summary.md')
    def super_review_path = File.join(log_dir, 'super-review.md')
    def manager_review_path = File.join(log_dir, 'manager_review.md')
    def manager_review_iteration_path(iteration) = File.join(log_dir, 'manager_reviews', "manager_review#{iteration}.md")
    def manager_findings_path(iteration) = File.join(log_dir, 'manager_reviews', "manager_review#{iteration}_findings.json")
    def manager_fix_result_path(iteration) = File.join(log_dir, 'manager_fixes', "manager_review_pi_fix#{iteration}_result.md")
    def manager_fix_review_path(iteration) = File.join(log_dir, 'manager_fixes', "manager_review_claude_fix_review#{iteration}_result.md")
    def final_check_review_path(review) = File.join(log_dir, 'reviews', "final_checks_claude_review#{review}_result.md")
    def super_fix_result_path(iteration) = File.join(log_dir, 'super_fixes', "super_review_pi_fix#{iteration}_result.md")
    def super_fix_review_path(iteration) = File.join(log_dir, 'super_fixes', "super_review_claude_fix_review#{iteration}_result.md")
    def prompt_path(name) = File.join(log_dir, 'prompts', name)
    def review_path(step, review) = File.join(log_dir, 'reviews', "step#{step}_claude_review#{review}_result.md")
    def resolution_path(step, review) = File.join(log_dir, 'resolutions', "step#{step}_pi_review#{review}_result.md")
    def debate_path(step) = File.join(log_dir, 'debates', "step#{step}_debates.md")
    def debate_claude_result_path(step, debate, round) = File.join(log_dir, 'debates', "step#{step}_debate_#{debate}_round#{round}_claude_result.md")
    def debate_pi_result_path(step, debate, round) = File.join(log_dir, 'debates', "step#{step}_debate_#{debate}_round#{round}_pi_result.md")
    def status_path(step, agent, phase, iteration = nil)
      suffix = iteration ? "#{phase}#{iteration}" : phase
      File.join(log_dir, 'status', "step#{step}_#{agent}_#{suffix}_status.json")
    end
  end

  class StateStore
    attr_reader :path

    def initialize(path)
      @path = path
    end

    def read
      raise Error, "Missing state file: #{path}" unless File.file?(path)

      data = JSON.parse(File.read(path))
      raise Error, "State file must contain a JSON object: #{path}" unless data.is_a?(Hash)

      data
    rescue JSON::ParserError => e
      raise Error, "Invalid state JSON in #{path}: #{e.message}"
    end

    def write(data)
      raise Error, 'State data must be a Hash' unless data.is_a?(Hash)

      data['updated_at'] = Time.now.iso8601
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, JSON.pretty_generate(data) + "\n")
    end
  end

  class RunLock
    attr_reader :path

    def initialize(path)
      @path = path
    end

    def acquire!
      FileUtils.mkdir_p(File.dirname(path))
      write_new_lock
    rescue Errno::EEXIST
      if stale?
        FileUtils.rm_f(path)
        retry
      end
      raise Error, "Autowork run is already locked by live pid #{lock_pid}: #{path}"
    end

    def release! = FileUtils.rm_f(path)

    def stale?
      pid = lock_pid
      return true unless pid

      !pid_alive?(pid)
    end

    def lock_pid
      return nil unless File.file?(path)

      pid = JSON.parse(File.read(path))['pid']
      pid.is_a?(Integer) ? pid : nil
    rescue JSON::ParserError
      nil
    end

    private

    def write_new_lock
      File.open(path, File::WRONLY | File::CREAT | File::EXCL) do |file|
        file.write(JSON.pretty_generate('pid' => Process.pid, 'created_at' => Time.now.iso8601) + "\n")
      end
      true
    end

    def pid_alive?(pid)
      Process.kill(0, pid)
      true
    rescue Errno::ESRCH
      false
    rescue Errno::EPERM
      true
    end
  end

  class PromptWriter
    def initialize(files, context, repo)
      @files = files
      @context = context
      @repo = repo
    end

    def final_status_action_note
      'After writing the status JSON, stop immediately. Do not run any more commands, inspect git status, edit files, or print an additional completion summary; `/autowork` may commit as soon as the status file appears.'
    end

    def pi_implement(step)
      path = @files.prompt_path("step#{step}_pi_implement_request.md")
      FileUtils.rm_f(@files.status_path(step, 'pi', 'implement'))
      File.write(path, <<~PROMPT)
        # Autowork: implement Step #{step}

        You are the Pi implementation agent participating in `/autowork` as `pi-worker`.

        Read:
        - task: #{File.join(@context.task_folder, 'task.md')}
        - steps: #{File.join(@context.task_folder, 'steps.md')}
        - autowork config: #{@files.config_path}
        - autowork state: #{@files.state_path}

        Implement only `## Step #{step}` from `steps.md`.

        Rules:
        - Work only in repo: #{@repo.root}
        - Do not commit.
        - Leave code changes unstaged/uncommitted for `/autowork` to commit.
        - Use idempotent file setup commands where safe, such as `mkdir -p qa-output` instead of `mkdir qa-output`, so retries/resumes do not fail on existing directories.
        - Treat `steps.md` as frozen. If the step is missing, stale, ambiguous, or impossible, stop and report that in the status file.
        - Create or update the requested files first, then run verification checks. Do not run exact-content checks for files that this step is about to create before writing them.
        - You may run targeted checks if useful.
        - Prefer simple read-only checks such as `test -f`, `cmp`, and `git status --short`.
        - Avoid heredoc interpreters such as `python3 - <<'PY'`, `ruby <<'RUBY'`, or `node <<'JS'` for routine content checks.
        - Avoid command substitution, backticks, and process substitution such as `$()`, `` `cmd` ``, `<(...)`, or `>(...)` for routine checks; these trigger broad shell execution permissions.
        - For exact text checks, avoid literal multiline expected strings. Prefer one argument per expected line: `printf '%s\\n' 'line 1' 'line 2' | cmp -s - path/to/file`.
        - When done, write valid JSON status to:
          #{@files.status_path(step, 'pi', 'implement')}
        - #{final_status_action_note}

        Required status JSON shape:

        ```json
        {
          "status": "done",
          "agent": "pi",
          "phase": "implement",
          "step": #{step},
          "summary": "...",
          "checks_run": []
        }
        ```

        If you need user input, use `"status": "needs_user"` and include a `"question"` string.
        If implementation failed, use `"status": "failed"` and explain in `"summary"`.
      PROMPT
      path
    end

    def claude_review(step, review, commit_sha)
      review_path = @files.review_path(step, review)
      status_path = @files.status_path(step, 'claude', 'review', review)
      path = @files.prompt_path("step#{step}_claude_review#{review}_request.md")
      FileUtils.rm_f(review_path)
      FileUtils.rm_f(status_path)
      File.write(path, <<~PROMPT)
        # Autowork: review Step #{step}, review #{review}

        You are the Claude review agent participating in `/autowork` as `claude-worker`.

        Review commit `#{commit_sha}` against Step #{step} only.

        Read:
        - task: #{File.join(@context.task_folder, 'task.md')}
        - steps: #{File.join(@context.task_folder, 'steps.md')}

        Rules:
        - Work in repo: #{@repo.root}
        - Do not edit repo files.
        - Scope findings to the current Step #{step}; do not require future-step behavior unless the current commit blocks or contradicts it.
        - Use `/gtm-revit`-style review depth.
        - Do not run RSpec, RuboCop, linters, formatters, or any other test/check command during normal step review — not full-suite and not targeted. Inspect the diff/files and Pi's reported `checks_run`; `/autowork` runs full final checks after all planned steps are accepted.
        - Classify checklist items with `PASS`, `MINOR`, or `BLOCKER`.
        - Prefer simple read-only checks such as `test -f`, `cmp`, `git show`, `git diff --exit-code`, `git diff-tree --no-commit-id --name-only -r HEAD`, and `git status --short`.
        - Avoid heredoc interpreters such as `python3 - <<'PY'`, `ruby <<'RUBY'`, or `node <<'JS'` for routine content checks.
        - Avoid command substitution, backticks, and process substitution such as `$()`, `` `cmd` ``, `<(...)`, or `>(...)` for routine checks; these trigger broad shell execution permissions.
        - For exact text checks, avoid literal multiline expected strings. Prefer one argument per expected line: `printf '%s\\n' 'line 1' 'line 2' | cmp -s - path/to/file`.
        - When reviewing a clean worktree after `/autowork` committed, compare expected content directly against the repo file path instead of against `git show` via process substitution.
        - Write the human-readable review to:
          #{review_path}
        - Write the review file before the status JSON.
        - Write the status JSON last. `/autowork` treats status JSON as the signal that all required artifacts for this turn are complete.
        - When done, write valid JSON status to:
          #{status_path}
        - #{final_status_action_note}

        Required review summary shape:

        ```text
        Summary: <N> BLOCKER / <M> MINOR / <K> PASS
        Recommendation: accept | fix | split
        ```

        Required status JSON shape:

        ```json
        {
          "status": "done",
          "agent": "claude",
          "phase": "review",
          "step": #{step},
          "summary": "...",
          "findings": [
            {
              "id": "B1",
              "severity": "BLOCKER",
              "title": "Short title",
              "body": "What is wrong and why it matters",
              "recommendation": "Concrete suggested fix"
            }
          ]
        }
        ```

        Use an empty `"findings": []` array when there are no `BLOCKER` or `MINOR` findings. `PASS` checklist notes may stay in the human review file and do not need status JSON entries.

        If you need user input, use `"status": "needs_user"` and include a `"question"` string.
        If review failed, use `"status": "failed"` and explain in `"summary"`.
      PROMPT
      path
    end

    def pi_classify(step, review, findings)
      resolution_path = @files.resolution_path(step, review)
      status_path = @files.status_path(step, 'pi', 'classify', review)
      path = @files.prompt_path("step#{step}_pi_classify_review#{review}_request.md")
      FileUtils.rm_f(resolution_path)
      FileUtils.rm_f(status_path)
      File.write(path, <<~PROMPT)
        # Autowork: classify Step #{step} review #{review} findings

        You are the Pi implementation agent participating in `/autowork` as `pi-worker`.

        Read:
        - task: #{File.join(@context.task_folder, 'task.md')}
        - steps: #{File.join(@context.task_folder, 'steps.md')}
        - Claude review: #{@files.review_path(step, review)}

        Claude reported these machine-readable findings:

        ```json
        #{JSON.pretty_generate(findings)}
        ```

        Classify every finding. Do not edit repo files in this classification turn.

        Allowed decisions:
        - `accept`: Claude is right; fix exactly this finding.
        - `accept_with_alternative_fix`: Claude is right, but use a different safe/local fix.
        - `dispute`: the finding is invalid or not reachable.
        - `follow_up`: the finding is valid, non-minor, and outside this task's scope; record it for the final summary instead of fixing now.
        - `needs_user`: user decision is required.

        Classification policy:
        - If the finding is clearly in scope of this task but outside the current step, choose `accept` or `accept_with_alternative_fix` and fix it now.
        - If the finding is `MINOR`, choose `accept` or `accept_with_alternative_fix` and fix it now, even when it is outside this task's original scope.
        - Use `follow_up` only for valid non-minor findings that are outside this task's scope.
        - Do not defer valid task-scope findings to a later step.

        Write human-readable rationale to:
        #{resolution_path}

        Write the resolution file before the status JSON.
        Write the status JSON last. `/autowork` treats status JSON as the signal that all required artifacts for this turn are complete.

        Then write valid JSON status to:
        #{status_path}

        #{final_status_action_note}

        Required status JSON shape:

        ```json
        {
          "status": "done",
          "agent": "pi",
          "phase": "classify",
          "step": #{step},
          "summary": "...",
          "resolutions": [
            {
              "finding_id": "B1",
              "decision": "accept",
              "rationale": "Why this decision is correct"
            }
          ]
        }
        ```
      PROMPT
      path
    end

    def pi_fix(step, fix_iteration, review, accepted_resolutions)
      status_path = @files.status_path(step, 'pi', 'fix', fix_iteration)
      path = @files.prompt_path("step#{step}_pi_fix#{fix_iteration}_request.md")
      FileUtils.rm_f(status_path)
      File.write(path, <<~PROMPT)
        # Autowork: fix Step #{step}, fix #{fix_iteration}

        You are the Pi implementation agent participating in `/autowork` as `pi-worker`.

        Read:
        - task: #{File.join(@context.task_folder, 'task.md')}
        - steps: #{File.join(@context.task_folder, 'steps.md')}
        - Claude review: #{@files.review_path(step, review)}
        - Pi resolution: #{@files.resolution_path(step, review)}

        Implement only these accepted findings/resolutions:

        ```json
        #{JSON.pretty_generate(accepted_resolutions)}
        ```

        Rules:
        - Work only in repo: #{@repo.root}
        - Do not commit.
        - Leave code changes unstaged/uncommitted for `/autowork` to commit.
        - Use idempotent file setup commands where safe, such as `mkdir -p qa-output` instead of `mkdir qa-output`, so retries/resumes do not fail on existing directories.
        - Do not implement disputed, deferred, or unrelated review comments.
        - Create or update the requested fixes first, then run verification checks. Do not run exact-content checks for files that this fix is about to create before writing them.
        - You may run targeted checks if useful.
        - Prefer simple read-only checks such as `test -f`, `cmp`, and `git status --short`.
        - Avoid heredoc interpreters such as `python3 - <<'PY'`, `ruby <<'RUBY'`, or `node <<'JS'` for routine content checks.
        - Avoid command substitution, backticks, and process substitution such as `$()`, `` `cmd` ``, `<(...)`, or `>(...)` for routine checks; these trigger broad shell execution permissions.
        - For exact text checks, avoid literal multiline expected strings. Prefer one argument per expected line: `printf '%s\\n' 'line 1' 'line 2' | cmp -s - path/to/file`.
        - When done, write valid JSON status to:
          #{status_path}
        - #{final_status_action_note}

        Required status JSON shape:

        ```json
        {
          "status": "done",
          "agent": "pi",
          "phase": "fix",
          "step": #{step},
          "summary": "...",
          "checks_run": []
        }
        ```
      PROMPT
      path
    end

    def pi_final_check_fix(iteration, final_checks, review_findings)
      status_path = @files.status_path(0, 'pi', 'final_checks_fix', iteration)
      path = @files.prompt_path("final_checks_pi_fix#{iteration}_request.md")
      FileUtils.rm_f(status_path)
      File.write(path, <<~PROMPT)
        # Autowork: fix final checks, iteration #{iteration}

        You are the Pi implementation agent participating in `/autowork` as `pi-worker`.

        Read:
        - task: #{File.join(@context.task_folder, 'task.md')}
        - steps: #{File.join(@context.task_folder, 'steps.md')}
        - final checks: #{@files.final_checks_path}

        Final check results:

        ```json
        #{JSON.pretty_generate(final_checks)}
        ```

        Claude final-check review findings to address, if any:

        ```json
        #{JSON.pretty_generate(review_findings || [])}
        ```

        Rules:
        - Work only in repo: #{@repo.root}
        - Do not commit.
        - Leave code changes unstaged/uncommitted for `/autowork` to commit.
        - Fix only the final-check failures and listed final-check review findings.
        - Prefer local, low-risk fixes.
        - Run targeted checks if useful.
        - When done, write valid JSON status to:
          #{status_path}
        - #{final_status_action_note}

        Required status JSON shape:

        ```json
        {
          "status": "done",
          "agent": "pi",
          "phase": "final_checks",
          "step": 0,
          "summary": "...",
          "checks_run": []
        }
        ```

        If you need user input, use `"status": "needs_user"` and include a `"question"` string.
        If the fix failed, use `"status": "failed"` and explain in `"summary"`.
      PROMPT
      path
    end

    def claude_final_check_review(review, commits)
      review_path = @files.final_check_review_path(review)
      status_path = @files.status_path(0, 'claude', 'final_checks_review', review)
      path = @files.prompt_path("final_checks_claude_review#{review}_request.md")
      FileUtils.rm_f(review_path)
      FileUtils.rm_f(status_path)
      File.write(path, <<~PROMPT)
        # Autowork: review final-check fix commits, review #{review}

        You are the Claude review agent participating in `/autowork` as `claude-worker`.

        Review these final-check fix commit(s):

        ```json
        #{JSON.pretty_generate(commits)}
        ```

        Read:
        - task: #{File.join(@context.task_folder, 'task.md')}
        - steps: #{File.join(@context.task_folder, 'steps.md')}
        - final checks: #{@files.final_checks_path}

        Rules:
        - Work in repo: #{@repo.root}
        - Do not edit repo files.
        - Scope findings to the final-check fix commits only.
        - Do not run RSpec, RuboCop, linters, formatters, or any other test/check command here — not full-suite and not targeted. `/autowork` already reran final checks before sending this review; inspect `final_checks.md` and the fix commits.
        - Classify checklist items with `PASS`, `MINOR`, or `BLOCKER`.
        - Write the human-readable review to:
          #{review_path}
        - Write the review file before status JSON.
        - Write valid JSON status last to:
          #{status_path}
        - #{final_status_action_note}

        Required status JSON shape:

        ```json
        {
          "status": "done",
          "agent": "claude",
          "phase": "final_checks",
          "step": 0,
          "summary": "...",
          "findings": []
        }
        ```

        Use an empty `"findings": []` array when there are no `BLOCKER` or `MINOR` findings.
        If you need user input, use `"status": "needs_user"` and include a `"question"` string.
        If review failed, use `"status": "failed"` and explain in `"summary"`.
      PROMPT
      path
    end

    def claude_final_super_review(iteration, review_base_ref)
      status_path = @files.status_path(0, 'claude', 'super_review', iteration)
      path = @files.prompt_path("final_super_review#{iteration}_request.md")
      FileUtils.rm_f(@files.super_review_path)
      FileUtils.rm_f(status_path)
      File.write(path, <<~PROMPT)
        # Autowork: final whole-branch super-review #{iteration}

        You are the Claude final review agent participating in `/autowork` as `claude-worker`.

        Run the `/claude-super-review` workflow in non-interactive autowork mode.

        Scope:
        - repo: #{@repo.root}
        - diff base: #{review_base_ref}
        - diff: `#{review_base_ref}...HEAD`

        Read:
        - task: #{File.join(@context.task_folder, 'task.md')}
        - steps: #{File.join(@context.task_folder, 'steps.md')}
        - final checks: #{@files.final_checks_path}
        - autowork state: #{@files.state_path}

        Autowork mode rules:
        - Review the whole final branch diff against `#{review_base_ref}...HEAD`.
        - Do not ask about posting comments.
        - Do not create pending GitHub comments.
        - Stop after the Phase 3/3.5 report.
        - Do not edit repo files.
        - Do not run RSpec, RuboCop, linters, formatters, or any other test/check command — not full-suite and not targeted. Inspect `final_checks.md` for already-run checks.
        - Save the human-readable report to:
          #{@files.super_review_path}
        - The report must include `Diff base: #{review_base_ref}`.
        - Write the report before status JSON.
        - Write valid JSON status last to:
          #{status_path}
        - #{final_status_action_note}

        Required status JSON shape:

        ```json
        {
          "status": "done",
          "agent": "claude",
          "phase": "super_review",
          "step": 0,
          "summary": "...",
          "findings": [
            {
              "id": "SR1",
              "severity": "BLOCKER",
              "title": "Short title",
              "body": "What is wrong and why it matters",
              "recommendation": "Concrete suggested fix"
            }
          ],
          "followups": [
            "Non-actionable advisory to carry into final_summary.md"
          ]
        }
        ```

        Map Critical/High super-review findings to `BLOCKER` in status JSON. Map actionable Medium findings to `MINOR`. Use an empty `findings` array when there are no actionable findings. Put non-actionable report-only advisories, later-story recommendations, and deploy/smoke-test notes in `followups` so they are not lost from the final summary. Use an empty `followups` array when there are none. Keep full Critical/High/Medium labels in the human-readable report if useful.

        If you need user input, use `"status": "needs_user"` and include a `"question"` string.
        If review failed, use `"status": "failed"` and explain in `"summary"`.
      PROMPT
      path
    end

    def pi_super_review_fix(iteration, findings, review_findings)
      result_path = @files.super_fix_result_path(iteration)
      status_path = @files.status_path(0, 'pi', 'super_fix', iteration)
      path = @files.prompt_path("super_review_pi_fix#{iteration}_request.md")
      FileUtils.rm_f(result_path)
      FileUtils.rm_f(status_path)
      File.write(path, <<~PROMPT)
        # Autowork: adjudicate/fix final super-review findings #{iteration}

        You are the Pi implementation agent participating in `/autowork` as `pi-worker`.

        Apply `/claude-super-fix` rules to the final super-review report: verify every finding, fix only real in-scope issues, reject noise/scope creep, and print follow-ups instead of mutating PR/MR metadata.

        Read:
        - task: #{File.join(@context.task_folder, 'task.md')}
        - steps: #{File.join(@context.task_folder, 'steps.md')}
        - final super-review report: #{@files.super_review_path}
        - final checks: #{@files.final_checks_path}

        Original super-review machine-readable findings:

        ```json
        #{JSON.pretty_generate(findings)}
        ```

        Claude's scoped review findings from the previous super-review fix attempt, if any:

        ```json
        #{JSON.pretty_generate(review_findings || [])}
        ```

        Rules:
        - Work only in repo: #{@repo.root}
        - Do not commit.
        - Leave code changes unstaged/uncommitted for `/autowork` to commit.
        - Do not stage, commit, push, switch branches, stash, or edit PR/MR metadata.
        - You have room to disagree with Claude. Do not blindly apply findings.
        - For every original finding, choose one decision: `accept`, `accept_with_alternative_fix`, `dispute`, `skip`, `already_fixed`, `out_of_scope`, `follow_up`, or `needs_user`.
        - If a valid finding is clearly in this task's scope, fix it now even when it was discovered late.
        - If a valid finding is `MINOR` or `MEDIUM`, fix it now even when it is outside this task's original scope, as long as it is minor/local/low-risk.
        - Use `follow_up` or `out_of_scope` only for valid non-minor findings outside this task's scope.
        - If you choose `accept` or `accept_with_alternative_fix`, apply the code fix in this same turn.
        - If Claude's previous scoped review found missed/incorrect fixes, address those too when valid.
        - Keep fixes narrow and safe.
        - Run focused checks if useful.
        - Print valid future cleanup as Follow-ups in the result file only; do not write issues or PR body updates.
        - Write human-readable adjudication/fix report to:
          #{result_path}
        - Write the result file before status JSON.
        - Write valid JSON status last to:
          #{status_path}
        - #{final_status_action_note}

        Required status JSON shape:

        ```json
        {
          "status": "done",
          "agent": "pi",
          "phase": "super_fix",
          "step": 0,
          "summary": "...",
          "resolutions": [
            {
              "finding_id": "SR1",
              "decision": "accept",
              "rationale": "Why this decision is correct"
            }
          ],
          "checks_run": [],
          "followups": []
        }
        ```

        If you need user input, use `"status": "needs_user"` and include a `"question"` string.
        If the fix failed, use `"status": "failed"` and explain in `"summary"`.
      PROMPT
      path
    end

    def claude_super_review_fix_review(iteration, commits)
      result_path = @files.super_fix_review_path(iteration)
      status_path = @files.status_path(0, 'claude', 'super_fix_review', iteration)
      path = @files.prompt_path("super_review_claude_fix_review#{iteration}_request.md")
      FileUtils.rm_f(result_path)
      FileUtils.rm_f(status_path)
      File.write(path, <<~PROMPT)
        # Autowork: scoped review of super-review fix #{iteration}

        You are the Claude review agent participating in `/autowork` as `claude-worker`.

        This is a normal scoped review, not another full `/claude-super-review`.

        Review:
        - final super-review report: #{@files.super_review_path}
        - Pi adjudication/fix report: #{@files.super_fix_result_path(iteration)}
        - final checks: #{@files.final_checks_path}
        - super-review fix commit(s):
          #{JSON.pretty_generate(commits)}

        Rules:
        - Work in repo: #{@repo.root}
        - Do not edit repo files.
        - Do not rerun full super-review.
        - Do not run RSpec, RuboCop, linters, formatters, or any other test/check command — not full-suite and not targeted. `/autowork` already reran final checks after the fix.
        - Verify accepted findings were fixed.
        - Verify Pi's disagreements/skips/follow-ups are reasonable from `task.md`, `steps.md`, and repo evidence.
        - Classify unresolved or incorrect decisions as `BLOCKER` or `MINOR` findings.
        - Write the human-readable review to:
          #{result_path}
        - Write the review file before status JSON.
        - Write valid JSON status last to:
          #{status_path}
        - #{final_status_action_note}

        Required status JSON shape:

        ```json
        {
          "status": "done",
          "agent": "claude",
          "phase": "super_fix_review",
          "step": 0,
          "summary": "...",
          "findings": []
        }
        ```

        Use an empty `findings` array when no further super-review-fix action is needed.
        If you need user input, use `"status": "needs_user"` and include a `"question"` string.
        If review failed, use `"status": "failed"` and explain in `"summary"`.
      PROMPT
      path
    end

    def pi_manager_fix(iteration, manager_review_iteration, manager_findings, review_findings)
      result_path = @files.manager_fix_result_path(iteration)
      status_path = @files.status_path(0, 'pi', 'manager_fix', iteration)
      path = @files.prompt_path("manager_review_pi_fix#{iteration}_request.md")
      FileUtils.rm_f(result_path)
      FileUtils.rm_f(status_path)
      findings_to_fix = Array(review_findings).empty? ? manager_findings : review_findings
      File.write(path, <<~PROMPT)
        # Autowork: manager production-readiness fix #{iteration}

        You are the Pi implementation agent participating in `/autowork` as `pi-worker`.

        The pi-manager used manager-only conversation context and found production-readiness issues. Fix them as mandatory task requirements. If repo evidence makes a finding impossible or contradictory, report `needs_user`; do not silently dispute or defer it.

        Read:
        - task: #{File.join(@context.task_folder, 'task.md')}
        - steps: #{File.join(@context.task_folder, 'steps.md')}
        - manager review: #{@files.manager_review_path}
        - manager findings: #{@files.manager_findings_path(manager_review_iteration)}
        - final checks: #{@files.final_checks_path}

        Original manager findings that must remain satisfied:

        ```json
        #{JSON.pretty_generate(manager_findings)}
        ```

        Findings to fix in this iteration:

        ```json
        #{JSON.pretty_generate(findings_to_fix)}
        ```

        Rules:
        - Work only in repo: #{@repo.root}
        - Do not commit.
        - Leave changes unstaged/uncommitted for `/autowork` to commit.
        - Do not stage, commit, push, switch branches, stash, rebase, or edit PR/MR metadata.
        - Fix every listed finding narrowly and keep all original manager findings satisfied.
        - Preserve task scope, data integrity, PII rules, and existing accepted behavior.
        - Add regression coverage for corrected behavior.
        - Run focused checks if useful. `/autowork` reruns configured full final checks after the commit.
        - Write a human-readable fix report to:
          #{result_path}
        - Write the report before status JSON.
        - Write valid JSON status last to:
          #{status_path}
        - #{final_status_action_note}

        Required status JSON shape:

        ```json
        {
          "status": "done",
          "agent": "pi",
          "phase": "manager_fix",
          "step": 0,
          "summary": "...",
          "checks_run": [],
          "followups": []
        }
        ```

        If a finding cannot be resolved safely without user input, use `"status": "needs_user"` and include a `"question"` string.
        If the fix failed, use `"status": "failed"` and explain why in `"summary"`.
      PROMPT
      path
    end

    def claude_manager_fix_review(iteration, manager_review_iteration, commit_sha, manager_findings)
      result_path = @files.manager_fix_review_path(iteration)
      status_path = @files.status_path(0, 'claude', 'manager_fix_review', iteration)
      path = @files.prompt_path("manager_review_claude_fix_review#{iteration}_request.md")
      FileUtils.rm_f(result_path)
      FileUtils.rm_f(status_path)
      File.write(path, <<~PROMPT)
        # Autowork: scoped review of manager production-readiness fix #{iteration}

        You are the Claude review agent participating in `/autowork` as `claude-worker`.

        Review manager-fix commit `#{commit_sha}`. This is a normal scoped review, not another whole-branch super-review.

        Read:
        - task: #{File.join(@context.task_folder, 'task.md')}
        - steps: #{File.join(@context.task_folder, 'steps.md')}
        - manager review: #{@files.manager_review_path}
        - manager findings: #{@files.manager_findings_path(manager_review_iteration)}
        - Pi fix report: #{@files.manager_fix_result_path(iteration)}
        - final checks: #{@files.final_checks_path}

        Manager findings that must be satisfied:

        ```json
        #{JSON.pretty_generate(manager_findings)}
        ```

        Rules:
        - Work in repo: #{@repo.root}
        - Do not edit repo files.
        - Review the manager-fix commit and enough surrounding code to verify the manager findings without regressing original task behavior.
        - Surface every `BLOCKER` and `MINOR` finding in one pass.
        - Do not run RSpec, RuboCop, linters, formatters, or other checks. `/autowork` reran full final checks after the fix; inspect `final_checks.md` and the commit.
        - Verify task intent, edge cases, data integrity, idempotency, PII rules, docs, and regression coverage affected by the fix.
        - Write the human-readable review to:
          #{result_path}
        - Write the review before status JSON.
        - Write valid JSON status last to:
          #{status_path}
        - #{final_status_action_note}

        Required status JSON shape:

        ```json
        {
          "status": "done",
          "agent": "claude",
          "phase": "manager_fix_review",
          "step": 0,
          "summary": "...",
          "findings": []
        }
        ```

        Use an empty `findings` array only when the manager fix is production-ready. If review needs user input, use `"status": "needs_user"` with a `"question"` string.
      PROMPT
      path
    end

    def claude_debate(step, review, debate_id, round, resolution)
      result_path = @files.debate_claude_result_path(step, debate_id, round)
      status_path = @files.status_path(step, 'claude', 'debate', "_#{debate_id}_round#{round}")
      path = @files.prompt_path("step#{step}_debate_#{debate_id}_round#{round}_claude_request.md")
      FileUtils.rm_f(result_path)
      FileUtils.rm_f(status_path)
      File.write(path, <<~PROMPT)
        # Autowork: debate Step #{step} finding #{debate_id}, round #{round} — Claude

        You are the Claude review agent participating in `/autowork` as `claude-worker`.

        Pi disputed or deferred this finding/resolution:

        ```json
        #{JSON.pretty_generate(resolution)}
        ```

        Read:
        - task: #{File.join(@context.task_folder, 'task.md')}
        - steps: #{File.join(@context.task_folder, 'steps.md')}
        - Claude review: #{@files.review_path(step, review)}
        - Pi resolution: #{@files.resolution_path(step, review)}
        - debate log: #{@files.debate_path(step)}

        Rules:
        - Work in repo: #{@repo.root}
        - Do not edit repo files.
        - Reply only about finding #{debate_id}.
        - Decide whether Pi's dispute/defer rationale resolves the concern.
        - Write your human-readable response to:
          #{result_path}
        - Write the response file before status JSON.
        - Write valid JSON status last to:
          #{status_path}
        - #{final_status_action_note}

        Required status JSON shape:

        ```json
        {
          "status": "done",
          "agent": "claude",
          "phase": "debate",
          "step": #{step},
          "summary": "agreement | still_disagree | needs_user: ...",
          "debate": {
            "finding_id": "#{debate_id}",
            "round": #{round},
            "decision": "agree_with_pi"
          }
        }
        ```

        Allowed debate decisions: `agree_with_pi`, `still_disagree`, `needs_user`.
        If you need user input, use top-level `"status": "needs_user"` and include a `"question"` string.
      PROMPT
      path
    end

    def pi_debate(step, review, debate_id, round, resolution)
      result_path = @files.debate_pi_result_path(step, debate_id, round)
      status_path = @files.status_path(step, 'pi', 'debate', "_#{debate_id}_round#{round}")
      path = @files.prompt_path("step#{step}_debate_#{debate_id}_round#{round}_pi_request.md")
      FileUtils.rm_f(result_path)
      FileUtils.rm_f(status_path)
      File.write(path, <<~PROMPT)
        # Autowork: debate Step #{step} finding #{debate_id}, round #{round} — Pi

        You are the Pi implementation agent participating in `/autowork` as `pi-worker`.

        Claude still disagrees about this finding/resolution:

        ```json
        #{JSON.pretty_generate(resolution)}
        ```

        Read:
        - task: #{File.join(@context.task_folder, 'task.md')}
        - steps: #{File.join(@context.task_folder, 'steps.md')}
        - Claude review: #{@files.review_path(step, review)}
        - Pi resolution: #{@files.resolution_path(step, review)}
        - latest Claude debate response: #{@files.debate_claude_result_path(step, debate_id, round)}
        - debate log: #{@files.debate_path(step)}

        Rules:
        - Do not edit repo files in this debate turn.
        - Reply only about finding #{debate_id}.
        - If Claude convinced you, choose `accept` or `accept_with_alternative_fix` so `/autowork` can send a fix turn.
        - If you still disagree or still defer, choose `still_disagree`.
        - Write your human-readable response to:
          #{result_path}
        - Write the response file before status JSON.
        - Write valid JSON status last to:
          #{status_path}
        - #{final_status_action_note}

        Required status JSON shape:

        ```json
        {
          "status": "done",
          "agent": "pi",
          "phase": "debate",
          "step": #{step},
          "summary": "...",
          "debate": {
            "finding_id": "#{debate_id}",
            "round": #{round},
            "decision": "still_disagree",
            "rationale": "..."
          }
        }
        ```

        Allowed debate decisions: `accept`, `accept_with_alternative_fix`, `still_disagree`, `needs_user`.
        If you need user input, use top-level `"status": "needs_user"` and include a `"question"` string.
      PROMPT
      path
    end
  end

  class RunSetup
    attr_reader :context, :repo, :steps, :roles, :files

    def initialize(argv, tmux: Tmux.new)
      @argv = argv
      @tmux = tmux
    end

    def prepare!
      @context = TaskResolver.new(@argv).resolve
      @repo = GitRepo.new(context.code_dir)
      raise Error, "Refusing to start with dirty worktree in #{repo.root}:\n#{repo.status}" unless repo.clean?
      ensure_safe_branch!

      @steps = Steps.new(File.join(context.task_folder, 'steps.md'))
      @roles = @tmux.discover_roles(repo.root)
      @files = RunFiles.new(context.task_folder)
      files.mkdirs
      write_config
      write_state
      PromptWriter.new(files, context, repo).pi_implement(steps.numbers.first)
      self
    end

    private

    def ensure_safe_branch!
      return if context.project == 'env'
      return unless %w[main master].include?(repo.branch)

      raise Error, "Refusing to run autowork on protected branch #{repo.branch.inspect} for #{context.project}. Switch to a task branch first."
    end

    def write_config
      config = {
        'task_folder' => context.task_folder,
        'task_project' => context.project,
        'task_id' => context.task_id,
        'repo_dir' => repo.root,
        'branch_name' => repo.branch,
        'starting_head_commit' => repo.head_sha_if_exists,
        'steps_count' => steps.count,
        'pi_manager_target' => roles.manager.id,
        'pi_worker_target' => roles.pi_worker.id,
        'claude_worker_target' => roles.claude_worker.id,
        'max_total_commits' => DEFAULT_MAX_TOTAL_COMMITS,
        'max_fix_iterations_per_step' => 10,
        'max_debate_rounds_per_disagreement' => 5,
        'max_final_check_fix_iterations' => 5,
        'max_super_review_fix_iterations' => 3,
        'max_manager_review_fix_iterations' => 5,
        'max_runtime_hours_per_run' => 1,
        'worker_status_timeout_minutes' => 10,
        'super_review_status_timeout_minutes' => 20,
        'run_final_super_review' => true,
        'original_review_base_ref' => review_base_ref,
        'original_review_base_commit' => recorded_review_base_commit,
        'review_base_ref' => review_base_ref,
        'review_base_ref_is_explicit' => !context.review_base_ref.nil?,
        'review_base_commit' => recorded_review_base_commit,
        'review_base_recorded_at' => Time.now.iso8601,
        'final_check_commands' => default_final_check_commands
      }
      File.write(files.config_path, config.to_yaml)
    end

    def review_base_ref
      @review_base_ref ||= context.review_base_ref || default_review_base_ref
    end

    def recorded_review_base_commit
      return repo.ref_commit(review_base_ref) if repo.ref_exists?(review_base_ref)
      raise Error, "Explicit review base ref does not resolve to a commit: #{review_base_ref}" if context.review_base_ref

      nil
    end

    def default_final_check_commands
      return [] unless File.file?(File.join(repo.root, 'Gemfile'))

      ['bundle exec rubocop', 'bundle exec rspec']
    end

    def default_review_base_ref
      return 'main' if repo.ref_exists?('main') || repo.ref_exists?('refs/heads/main')
      return 'origin/main' if repo.ref_exists?('origin/main')
      return 'master' if repo.ref_exists?('master') || repo.ref_exists?('refs/heads/master')
      return 'origin/master' if repo.ref_exists?('origin/master')

      repo.branch == 'master' ? 'master' : 'main'
    end

    def write_state
      now = Time.now.iso8601
      state = {
        'status' => 'initialized',
        'phase' => 'ready_to_send_pi_implement',
        'current_step' => steps.numbers.first,
        'next_action' => 'send_pi_implement_prompt',
        'created_at' => now,
        'updated_at' => now,
        'original_review_base_ref' => review_base_ref,
        'original_review_base_commit' => recorded_review_base_commit,
        'review_base_ref' => review_base_ref,
        'review_base_commit' => recorded_review_base_commit,
        'steps' => steps.numbers.to_h { |number| [number.to_s, { 'status' => 'pending', 'commits' => [], 'reviews' => [] }] }
      }
      StateStore.new(files.state_path).write(state)
    end
  end

  class Orchestrator
    def initialize(argv, tmux: Tmux.new, sleeper: Kernel.method(:sleep))
      @argv = argv
      @tmux = tmux
      @sleeper = sleeper
    end

    def run
      context = TaskResolver.new(@argv).resolve
      files = RunFiles.new(context.task_folder)
      files.mkdirs
      setup = setup_if_needed(context, files)
      repo = setup&.repo || GitRepo.new(context.code_dir)
      lock = RunLock.new(files.lock_path)
      lock.acquire!
      begin
        run_state_machine(context, repo, files)
      ensure
        lock.release!
      end
    end

    private

    def setup_if_needed(context, files)
      return nil if File.file?(files.config_path) && File.file?(files.state_path)

      setup = RunSetup.new(@argv, tmux: @tmux).prepare!
      puts "Initialized autowork run for #{setup.context.task_folder}"
      setup
    end

    def run_state_machine(context, repo, files)
      raise Error, "Autowork is paused: #{files.pause_path}" if File.file?(files.pause_path)

      config = YAML.safe_load(File.read(files.config_path))
      store = StateStore.new(files.state_path)
      state = store.read
      ensure_review_base_current!(repo, files, config, store, state) if review_base_check_phase?(state['phase'])
      case state['phase']
      when 'ready_to_send_pi_implement'
        send_pi_implement(context, repo, files, config, store, state)
      when 'waiting_for_pi_implement'
        wait_for_pi_implement(context, repo, files, config, store, state)
      when 'ready_to_commit_step'
        commit_step(context, repo, files, config, store, state)
      when 'ready_to_send_claude_review'
        send_claude_review(context, repo, files, config, store, state)
      when 'waiting_for_claude_review'
        wait_for_claude_review(context, repo, files, config, store, state)
      when 'ready_to_send_pi_classify'
        send_pi_classify(context, repo, files, config, store, state)
      when 'waiting_for_pi_classify'
        wait_for_pi_classify(context, repo, files, config, store, state)
      when 'ready_to_send_pi_fix'
        send_pi_fix(context, repo, files, config, store, state)
      when 'waiting_for_pi_fix'
        wait_for_pi_fix(context, repo, files, config, store, state)
      when 'ready_to_commit_fix'
        commit_fix(context, repo, files, config, store, state)
      when 'ready_to_send_claude_debate'
        send_claude_debate(context, repo, files, config, store, state)
      when 'waiting_for_claude_debate'
        wait_for_claude_debate(context, repo, files, config, store, state)
      when 'ready_to_send_pi_debate'
        send_pi_debate(context, repo, files, config, store, state)
      when 'waiting_for_pi_debate'
        wait_for_pi_debate(context, repo, files, config, store, state)
      when 'step_accepted'
        advance_after_step(context, repo, files, config, store, state)
      when 'ready_to_run_final_checks', 'all_steps_accepted'
        run_final_checks(context, repo, files, config, store, state)
      when 'ready_to_send_final_super_review'
        send_final_super_review(context, repo, files, config, store, state)
      when 'waiting_for_final_super_review'
        wait_for_final_super_review(context, repo, files, config, store, state)
      when 'ready_to_send_pi_super_review_fix'
        send_pi_super_review_fix(context, repo, files, config, store, state)
      when 'waiting_for_pi_super_review_fix'
        wait_for_pi_super_review_fix(context, repo, files, config, store, state)
      when 'ready_to_commit_super_review_fix'
        commit_super_review_fix(context, repo, files, config, store, state)
      when 'ready_to_send_claude_super_review_fix_review'
        send_claude_super_review_fix_review(context, repo, files, config, store, state)
      when 'waiting_for_claude_super_review_fix_review'
        wait_for_claude_super_review_fix_review(context, repo, files, config, store, state)
      when 'ready_to_send_pi_manager_fix'
        send_pi_manager_fix(context, repo, files, config, store, state)
      when 'waiting_for_pi_manager_fix'
        wait_for_pi_manager_fix(context, repo, files, config, store, state)
      when 'ready_to_commit_manager_fix'
        commit_manager_fix(context, repo, files, config, store, state)
      when 'ready_to_send_claude_manager_fix_review'
        send_claude_manager_fix_review(context, repo, files, config, store, state)
      when 'waiting_for_claude_manager_fix_review'
        wait_for_claude_manager_fix_review(context, repo, files, config, store, state)
      when 'ready_for_manager_final_review'
        print_manager_final_review_instructions(repo, files, state)
      when 'ready_to_send_pi_final_check_fix'
        send_pi_final_check_fix(context, repo, files, config, store, state)
      when 'waiting_for_pi_final_check_fix'
        wait_for_pi_final_check_fix(context, repo, files, config, store, state)
      when 'ready_to_commit_final_check_fix'
        commit_final_check_fix(context, repo, files, config, store, state)
      when 'ready_to_send_claude_final_check_review'
        send_claude_final_check_review(context, repo, files, config, store, state)
      when 'waiting_for_claude_final_check_review'
        wait_for_claude_final_check_review(context, repo, files, config, store, state)
      when 'complete'
        puts "Autowork complete. Summary: #{files.final_summary_path}"
      else
        raise Error, "Unknown autowork phase: #{state['phase'].inspect}"
      end
    end

    def review_base_check_phase?(phase)
      phase && !phase.start_with?('waiting_') && phase != 'complete'
    end

    def ensure_review_base_current!(repo, files, config, store, state)
      return unless config['review_base_ref_is_explicit']

      review_base_ref = config['review_base_ref']
      return if review_base_ref.to_s.empty?

      current_commit = repo.ref_commit(review_base_ref)
      recorded_commit = config['review_base_commit']
      unless recorded_commit
        config['review_base_commit'] = current_commit
        config['review_base_recorded_at'] = Time.now.iso8601
        File.write(files.config_path, config.to_yaml)
        return
      end
      return if current_commit == recorded_commit

      relationship = repo.ancestor?(recorded_commit, current_commit) ? 'advanced' : 'changed'
      pause_with_reason!(files, store, state, <<~MSG.chomp)
        Review base ref #{review_base_ref} #{relationship} since this autowork run recorded it.
        Recorded base commit: #{recorded_commit}
        Current base commit: #{current_commit}

        Do not continue on the old base by default. Rebase/change the task branch only with explicit approval. After the intended base is correct, run:
        autowork update-base #{files.task_folder} #{review_base_ref}
        Or, if the parent was merged and this task should now be based on main/master, run:
        autowork update-base #{files.task_folder} <new-base-ref>
      MSG
    rescue Error
      raise
    rescue StandardError => e
      pause_with_reason!(files, store, state, "Review base ref #{review_base_ref} no longer resolves cleanly: #{e.message}")
    end

    def send_pi_implement(context, repo, files, config, store, state)
      raise Error, "Refusing to send Pi work with dirty baseline in #{repo.root}:\n#{repo.status}" unless repo.clean?

      step = state['current_step']
      prompt = PromptWriter.new(files, context, repo).pi_implement(step)
      @tmux.send_prompt(config.fetch('pi_worker_target'), prompt)
      state['status'] = 'running'
      state['phase'] = 'waiting_for_pi_implement'
      state['next_action'] = 'wait_for_pi_implement_status'
      store.write(state)
      puts "Sent Step #{step} implementation prompt to pi-worker: #{prompt}"
      wait_for_pi_implement(context, repo, files, config, store, state)
    end

    def wait_for_pi_implement(context, repo, files, config, store, state)
      step = state['current_step']
      result = wait_for_status(files.status_path(step, 'pi', 'implement'), expected: { agent: 'pi', phase: 'implement', step: step }, config: config)
      handle_agent_status!(result, files, store, state)
      state['phase'] = 'ready_to_commit_step'
      state['next_action'] = 'commit_step'
      store.write(state)
      commit_step(context, repo, files, config, store, state)
    end

    def commit_step(context, repo, files, config, store, state)
      step = state['current_step']
      raise Error, "No changes to commit for Step #{step}; pi-worker status was done but worktree is clean" if repo.clean?

      ensure_commit_budget!(files, store, state, config)
      repo.add_all
      commit_sha = repo.commit("Step #{step}")
      raise Error, "Worktree is dirty after Step #{step} commit:\n#{repo.status}" unless repo.clean?

      state.dig('steps', step.to_s, 'commits') << commit_sha
      state['last_commit'] = commit_sha
      state['review_iteration'] = 1
      state['phase'] = 'ready_to_send_claude_review'
      state['next_action'] = 'send_claude_review_prompt'
      store.write(state)
      puts "Committed Step #{step}: #{commit_sha}"
      send_claude_review(context, repo, files, config, store, state)
    end

    def send_claude_review(context, repo, files, config, store, state)
      raise Error, "Refusing to send Claude review with dirty worktree in #{repo.root}:\n#{repo.status}" unless repo.clean?

      step = state['current_step']
      review = state['review_iteration'] || 1
      prompt = PromptWriter.new(files, context, repo).claude_review(step, review, state.fetch('last_commit'))
      @tmux.send_prompt(config.fetch('claude_worker_target'), prompt)
      state['status'] = 'running'
      state['phase'] = 'waiting_for_claude_review'
      state['next_action'] = 'wait_for_claude_review_status'
      store.write(state)
      puts "Sent Step #{step} review prompt to claude-worker: #{prompt}"
      wait_for_claude_review(context, repo, files, config, store, state)
    end

    def wait_for_claude_review(context, repo, files, config, store, state)
      step = state['current_step']
      review = state['review_iteration'] || 1
      result = wait_for_status(files.status_path(step, 'claude', 'review', review), expected: { agent: 'claude', phase: 'review', step: step }, config: config)
      handle_agent_status!(result, files, store, state)
      require_nonempty_artifact!(files.review_path(step, review), 'Claude review')
      raise Error, "Claude review changed repo files; worktree must remain clean:\n#{repo.status}" unless repo.clean?

      findings = actionable_findings(result.data)
      state.dig('steps', step.to_s, 'reviews') << { 'iteration' => review, 'status' => 'done', 'summary' => result.data['summary'], 'findings_count' => findings.count }
      if findings.empty?
        state.dig('steps', step.to_s)['status'] = 'accepted'
        state['phase'] = 'step_accepted'
        state['next_action'] = 'advance_after_step'
        store.write(state)
        puts "Step #{step} review #{review} completed with no actionable findings."
        advance_after_step(context, repo, files, config, store, state)
      else
        state['current_findings'] = findings
        state['phase'] = 'ready_to_send_pi_classify'
        state['next_action'] = 'send_pi_classify_prompt'
        store.write(state)
        puts "Step #{step} review #{review} completed with #{findings.count} actionable finding(s)."
        send_pi_classify(context, repo, files, config, store, state)
      end
    end

    def send_pi_classify(context, repo, files, config, store, state)
      raise Error, "Refusing to classify findings with dirty worktree in #{repo.root}:\n#{repo.status}" unless repo.clean?

      step = state['current_step']
      review = state['review_iteration'] || 1
      findings = state.fetch('current_findings')
      prompt = PromptWriter.new(files, context, repo).pi_classify(step, review, findings)
      @tmux.send_prompt(config.fetch('pi_worker_target'), prompt)
      state['status'] = 'running'
      state['phase'] = 'waiting_for_pi_classify'
      state['next_action'] = 'wait_for_pi_classify_status'
      store.write(state)
      puts "Sent Step #{step} review #{review} classification prompt to pi-worker: #{prompt}"
      wait_for_pi_classify(context, repo, files, config, store, state)
    end

    def wait_for_pi_classify(context, repo, files, config, store, state)
      step = state['current_step']
      review = state['review_iteration'] || 1
      result = wait_for_status(files.status_path(step, 'pi', 'classify', review), expected: { agent: 'pi', phase: 'classify', step: step }, config: config)
      handle_agent_status!(result, files, store, state)
      require_nonempty_artifact!(files.resolution_path(step, review), 'Pi resolution')
      raise Error, "Pi classification changed repo files; worktree must remain clean:\n#{repo.status}" unless repo.clean?

      findings = state.fetch('current_findings')
      resolutions = result.data.fetch('resolutions', [])
      validate_resolution_coverage!(findings, resolutions)
      validate_follow_up_severity!(findings, resolutions)
      state['current_resolutions'] = resolutions
      needs_user = resolutions.select { |resolution| resolution['decision'] == 'needs_user' }
      pause_for_needs_user!(needs_user, files, store, state) unless needs_user.empty?

      follow_ups = follow_up_resolutions(resolutions)
      record_step_review_followups(state, follow_ups) unless follow_ups.empty?
      accepted = accepted_resolutions(resolutions)
      unresolved = unresolved_resolutions(resolutions)
      record_unresolved_findings(files, state, unresolved) unless unresolved.empty?
      if accepted.empty?
        unless unresolved.empty?
          state['current_debate_resolutions'] = unresolved
          state['debate_index'] = 0
          state['debate_round'] = 1
          state['phase'] = 'ready_to_send_claude_debate'
          state['next_action'] = 'send_claude_debate_prompt'
          store.write(state)
          send_claude_debate(context, repo, files, config, store, state)
          return
        end
        state.dig('steps', step.to_s)['status'] = 'accepted'
        state['phase'] = 'step_accepted'
        state['next_action'] = 'advance_after_step'
        store.write(state)
        advance_after_step(context, repo, files, config, store, state)
      else
        state['accepted_resolutions'] = accepted
        state['fix_iteration'] = (state['fix_iteration'] || 0) + 1
        state['phase'] = 'ready_to_send_pi_fix'
        state['next_action'] = 'send_pi_fix_prompt'
        store.write(state)
        send_pi_fix(context, repo, files, config, store, state)
      end
    end

    def send_pi_fix(context, repo, files, config, store, state)
      raise Error, "Refusing to send Pi fix with dirty baseline in #{repo.root}:\n#{repo.status}" unless repo.clean?

      step = state['current_step']
      review = state['review_iteration'] || 1
      fix_iteration = state.fetch('fix_iteration')
      prompt = PromptWriter.new(files, context, repo).pi_fix(step, fix_iteration, review, state.fetch('accepted_resolutions'))
      @tmux.send_prompt(config.fetch('pi_worker_target'), prompt)
      state['status'] = 'running'
      state['phase'] = 'waiting_for_pi_fix'
      state['next_action'] = 'wait_for_pi_fix_status'
      store.write(state)
      puts "Sent Step #{step} fix #{fix_iteration} prompt to pi-worker: #{prompt}"
      wait_for_pi_fix(context, repo, files, config, store, state)
    end

    def wait_for_pi_fix(context, repo, files, config, store, state)
      step = state['current_step']
      fix_iteration = state.fetch('fix_iteration')
      result = wait_for_status(files.status_path(step, 'pi', 'fix', fix_iteration), expected: { agent: 'pi', phase: 'fix', step: step }, config: config)
      handle_agent_status!(result, files, store, state)
      state['phase'] = 'ready_to_commit_fix'
      state['next_action'] = 'commit_fix'
      store.write(state)
      commit_fix(context, repo, files, config, store, state)
    end

    def commit_fix(context, repo, files, config, store, state)
      step = state['current_step']
      fix_iteration = state.fetch('fix_iteration')
      raise Error, "No changes to commit for Step #{step} fix #{fix_iteration}; pi-worker status was done but worktree is clean" if repo.clean?

      ensure_commit_budget!(files, store, state, config)
      repo.add_all
      commit_sha = repo.commit("Step #{step} fix #{fix_iteration}")
      raise Error, "Worktree is dirty after Step #{step} fix #{fix_iteration} commit:\n#{repo.status}" unless repo.clean?

      state.dig('steps', step.to_s, 'commits') << commit_sha
      state['last_commit'] = commit_sha
      state['review_iteration'] = (state['review_iteration'] || 1) + 1
      state.delete('current_findings')
      state.delete('current_resolutions')
      state.delete('accepted_resolutions')
      state.delete('current_debate_resolutions')
      state.delete('debate_index')
      state.delete('debate_round')
      state['phase'] = 'ready_to_send_claude_review'
      state['next_action'] = 'send_claude_review_prompt'
      store.write(state)
      puts "Committed Step #{step} fix #{fix_iteration}: #{commit_sha}"
      send_claude_review(context, repo, files, config, store, state)
    end

    def send_claude_debate(context, repo, files, config, store, state)
      raise Error, "Refusing to send Claude debate with dirty worktree in #{repo.root}:\n#{repo.status}" unless repo.clean?

      step = state['current_step']
      review = state['review_iteration'] || 1
      round = state.fetch('debate_round')
      resolution = current_debate_resolution(state)
      debate_id = resolution.fetch('finding_id')
      prompt = PromptWriter.new(files, context, repo).claude_debate(step, review, debate_id, round, resolution)
      @tmux.send_prompt(config.fetch('claude_worker_target'), prompt)
      state['status'] = 'running'
      state['phase'] = 'waiting_for_claude_debate'
      state['next_action'] = 'wait_for_claude_debate_status'
      store.write(state)
      puts "Sent Step #{step} debate #{debate_id} round #{round} prompt to claude-worker: #{prompt}"
      wait_for_claude_debate(context, repo, files, config, store, state)
    end

    def wait_for_claude_debate(context, repo, files, config, store, state)
      step = state['current_step']
      round = state.fetch('debate_round')
      resolution = current_debate_resolution(state)
      debate_id = resolution.fetch('finding_id')
      result = wait_for_status(files.status_path(step, 'claude', 'debate', "_#{debate_id}_round#{round}"), expected: { agent: 'claude', phase: 'debate', step: step }, config: config)
      handle_agent_status!(result, files, store, state)
      require_nonempty_artifact!(files.debate_claude_result_path(step, debate_id, round), 'Claude debate')
      raise Error, "Claude debate changed repo files; worktree must remain clean:\n#{repo.status}" unless repo.clean?

      decision = debate_decision!(result.data, %w[agree_with_pi still_disagree needs_user])
      append_debate_turn(files, state, 'Claude', debate_id, round, result.data['summary'])
      case decision
      when 'agree_with_pi'
        append_debate_turn(files, state, 'Decision', debate_id, round, 'Claude agrees with Pi; no code change required for this finding.')
        advance_debate_or_accept_step(context, repo, files, config, store, state)
      when 'still_disagree'
        state['phase'] = 'ready_to_send_pi_debate'
        state['next_action'] = 'send_pi_debate_prompt'
        store.write(state)
        send_pi_debate(context, repo, files, config, store, state)
      when 'needs_user'
        pause_with_reason!(files, store, state, "Claude requested user arbitration for debate #{debate_id}: #{result.data['summary']}")
      end
    end

    def send_pi_debate(context, repo, files, config, store, state)
      raise Error, "Refusing to send Pi debate with dirty worktree in #{repo.root}:\n#{repo.status}" unless repo.clean?

      step = state['current_step']
      review = state['review_iteration'] || 1
      round = state.fetch('debate_round')
      resolution = current_debate_resolution(state)
      debate_id = resolution.fetch('finding_id')
      prompt = PromptWriter.new(files, context, repo).pi_debate(step, review, debate_id, round, resolution)
      @tmux.send_prompt(config.fetch('pi_worker_target'), prompt)
      state['status'] = 'running'
      state['phase'] = 'waiting_for_pi_debate'
      state['next_action'] = 'wait_for_pi_debate_status'
      store.write(state)
      puts "Sent Step #{step} debate #{debate_id} round #{round} prompt to pi-worker: #{prompt}"
      wait_for_pi_debate(context, repo, files, config, store, state)
    end

    def wait_for_pi_debate(context, repo, files, config, store, state)
      step = state['current_step']
      round = state.fetch('debate_round')
      resolution = current_debate_resolution(state)
      debate_id = resolution.fetch('finding_id')
      result = wait_for_status(files.status_path(step, 'pi', 'debate', "_#{debate_id}_round#{round}"), expected: { agent: 'pi', phase: 'debate', step: step }, config: config)
      handle_agent_status!(result, files, store, state)
      require_nonempty_artifact!(files.debate_pi_result_path(step, debate_id, round), 'Pi debate')
      raise Error, "Pi debate changed repo files; worktree must remain clean:\n#{repo.status}" unless repo.clean?

      decision = debate_decision!(result.data, %w[accept accept_with_alternative_fix still_disagree needs_user])
      append_debate_turn(files, state, 'Pi', debate_id, round, result.data['summary'])
      case decision
      when 'accept', 'accept_with_alternative_fix'
        state['accepted_resolutions'] = [{
          'finding_id' => debate_id,
          'decision' => decision,
          'rationale' => result.data.dig('debate', 'rationale') || result.data['summary']
        }]
        state['fix_iteration'] = (state['fix_iteration'] || 0) + 1
        state['phase'] = 'ready_to_send_pi_fix'
        state['next_action'] = 'send_pi_fix_prompt'
        store.write(state)
        send_pi_fix(context, repo, files, config, store, state)
      when 'still_disagree'
        if round >= config.fetch('max_debate_rounds_per_disagreement', 5).to_i
          pause_with_reason!(files, store, state, "Pi and Claude still disagree about #{debate_id} after #{round} debate round(s). See #{files.debate_path(step)}")
        end
        state['debate_round'] = round + 1
        state['phase'] = 'ready_to_send_claude_debate'
        state['next_action'] = 'send_claude_debate_prompt'
        store.write(state)
        send_claude_debate(context, repo, files, config, store, state)
      when 'needs_user'
        pause_with_reason!(files, store, state, "Pi requested user arbitration for debate #{debate_id}: #{result.data['summary']}")
      end
    end

    def current_debate_resolution(state)
      resolutions = state.fetch('current_debate_resolutions')
      index = state.fetch('debate_index')
      resolutions.fetch(index)
    end

    def debate_decision!(data, allowed)
      debate = data['debate']
      raise Error, 'Debate status must include debate object' unless debate.is_a?(Hash)

      decision = debate['decision']
      raise Error, "Debate decision must be one of #{allowed.join(', ')}" unless allowed.include?(decision)

      decision
    end

    def append_debate_turn(files, state, speaker, debate_id, round, text)
      step = state['current_step']
      File.open(files.debate_path(step), 'a') do |file|
        file.puts "### Round #{round} — #{speaker} — #{debate_id}"
        file.puts
        file.puts text
        file.puts
      end
    end

    def advance_debate_or_accept_step(context, repo, files, config, store, state)
      next_index = state.fetch('debate_index') + 1
      if next_index < state.fetch('current_debate_resolutions').length
        state['debate_index'] = next_index
        state['debate_round'] = 1
        state['phase'] = 'ready_to_send_claude_debate'
        state['next_action'] = 'send_claude_debate_prompt'
        store.write(state)
        send_claude_debate(context, repo, files, config, store, state)
      else
        step = state['current_step']
        state.dig('steps', step.to_s)['status'] = 'accepted'
        state.delete('current_findings')
        state.delete('current_resolutions')
        state.delete('current_debate_resolutions')
        state.delete('debate_index')
        state.delete('debate_round')
        state['phase'] = 'step_accepted'
        state['next_action'] = 'advance_after_step'
        store.write(state)
        advance_after_step(context, repo, files, config, store, state)
      end
    end

    def advance_after_step(context, repo, files, config, store, state)
      ensure_review_base_current!(repo, files, config, store, state)
      steps = state.fetch('steps').keys.map(&:to_i).sort
      current = state.fetch('current_step')
      next_step = steps.find { |step| step > current }
      if next_step
        state['current_step'] = next_step
        state['phase'] = 'ready_to_send_pi_implement'
        state['next_action'] = 'send_pi_implement_prompt'
        state.delete('last_commit')
        state.delete('review_iteration')
        state.delete('fix_iteration')
        store.write(state)
        puts "Advancing to Step #{next_step}."
        send_pi_implement(context, repo, files, config, store, state)
      else
        state['status'] = 'running'
        state['phase'] = 'ready_to_run_final_checks'
        state['next_action'] = 'run_final_checks'
        store.write(state)
        puts 'All planned steps are accepted. Running final checks.'
        run_final_checks(context, repo, files, config, store, state)
      end
    end

    def run_final_checks(context, repo, files, config, store, state)
      raise Error, "Refusing to run final checks with dirty worktree in #{repo.root}:\n#{repo.status}" unless repo.clean?

      commands = Array(config.fetch('final_check_commands', []))
      results = commands.empty? ? skipped_final_check_results : execute_final_check_commands(repo, commands)
      write_final_checks(files, results)
      state['final_checks'] = compact_final_check_results(results)
      failures = compact_final_check_results(results.reject { |result| result.fetch('status') == 'passed' || result.fetch('status') == 'skipped' })
      if failures.empty?
        if !final_check_fix_commits(state).empty? && !state['final_check_reviewed']
          state['phase'] = 'ready_to_send_claude_final_check_review'
          state['next_action'] = 'send_claude_final_check_review_prompt'
          store.write(state)
          send_claude_final_check_review(context, repo, files, config, store, state)
        else
          continue_after_passing_final_checks(context, repo, files, config, store, state, results)
        end
        return
      end

      state['final_check_failures'] = failures
      state['phase'] = 'ready_to_send_pi_final_check_fix'
      state['next_action'] = 'send_pi_final_check_fix_prompt'
      store.write(state)
      send_pi_final_check_fix(context, repo, files, config, store, state)
    end

    def continue_after_passing_final_checks(context, repo, files, config, store, state, results)
      if state['pending_manager_fix_review']
        state['phase'] = 'ready_to_send_claude_manager_fix_review'
        state['next_action'] = 'send_claude_manager_fix_review_prompt'
        store.write(state)
        send_claude_manager_fix_review(context, repo, files, config, store, state)
      elsif state['pending_super_review_fix_review']
        state['phase'] = 'ready_to_send_claude_super_review_fix_review'
        state['next_action'] = 'send_claude_super_review_fix_review_prompt'
        store.write(state)
        send_claude_super_review_fix_review(context, repo, files, config, store, state)
      elsif final_super_review_required?(config, state)
        state['phase'] = 'ready_to_send_final_super_review'
        state['next_action'] = 'send_final_super_review_prompt'
        store.write(state)
        send_final_super_review(context, repo, files, config, store, state)
      else
        complete_run(context, repo, files, store, state, results)
      end
    end

    def final_super_review_required?(config, state)
      config.fetch('run_final_super_review', true) && !state['final_super_reviewed']
    end

    def send_final_super_review(context, repo, files, config, store, state)
      raise Error, "Refusing to send final super-review with dirty worktree in #{repo.root}:\n#{repo.status}" unless repo.clean?

      iteration = (state['final_super_review_iteration'] || 0) + 1
      prompt = PromptWriter.new(files, context, repo).claude_final_super_review(iteration, config.fetch('review_base_ref'))
      @tmux.send_prompt(config.fetch('claude_worker_target'), prompt)
      state['status'] = 'running'
      state['final_super_review_iteration'] = iteration
      state['phase'] = 'waiting_for_final_super_review'
      state['next_action'] = 'wait_for_final_super_review_status'
      store.write(state)
      puts "Sent final super-review #{iteration} prompt to claude-worker: #{prompt}"
      wait_for_final_super_review(context, repo, files, config, store, state)
    end

    def wait_for_final_super_review(context, repo, files, config, store, state)
      iteration = state.fetch('final_super_review_iteration')
      result = wait_for_status(
        files.status_path(0, 'claude', 'super_review', iteration),
        expected: { agent: 'claude', phase: 'super_review', step: 0 },
        config: config,
        timeout_seconds: super_review_status_timeout_seconds(config)
      )
      handle_agent_status!(result, files, store, state)
      require_nonempty_artifact!(files.super_review_path, 'Final super-review')
      raise Error, "Final super-review changed repo files; worktree must remain clean:\n#{repo.status}" unless repo.clean?

      findings = super_review_findings(result.data)
      state['final_super_review_summary'] = result.data['summary']
      state['final_super_review_findings'] = findings
      state['final_super_review_followups'] = Array(result.data['followups'])
      if findings.empty?
        state['final_super_reviewed'] = true
        store.write(state)
        complete_run(context, repo, files, store, state, state.fetch('final_checks'))
      else
        state['phase'] = 'ready_to_send_pi_super_review_fix'
        state['next_action'] = 'send_pi_super_review_fix_prompt'
        store.write(state)
        send_pi_super_review_fix(context, repo, files, config, store, state)
      end
    end

    def send_pi_super_review_fix(context, repo, files, config, store, state)
      raise Error, "Refusing to send Pi super-review fix with dirty baseline in #{repo.root}:\n#{repo.status}" unless repo.clean?

      iteration = (state['super_review_fix_iteration'] || 0) + 1
      if iteration > config.fetch('max_super_review_fix_iterations', 3).to_i
        pause_with_reason!(files, store, state, "Super-review findings still need work after #{iteration - 1} fix iteration(s). See #{files.super_review_path}")
      end
      prompt = PromptWriter.new(files, context, repo).pi_super_review_fix(iteration, state.fetch('final_super_review_findings', []), state['super_review_fix_review_findings'])
      @tmux.send_prompt(config.fetch('pi_worker_target'), prompt)
      state['status'] = 'running'
      state['super_review_fix_iteration'] = iteration
      state['phase'] = 'waiting_for_pi_super_review_fix'
      state['next_action'] = 'wait_for_pi_super_review_fix_status'
      store.write(state)
      puts "Sent super-review fix #{iteration} prompt to pi-worker: #{prompt}"
      wait_for_pi_super_review_fix(context, repo, files, config, store, state)
    end

    def wait_for_pi_super_review_fix(context, repo, files, config, store, state)
      iteration = state.fetch('super_review_fix_iteration')
      result = wait_for_status(files.status_path(0, 'pi', 'super_fix', iteration), expected: { agent: 'pi', phase: 'super_fix', step: 0 }, config: config)
      handle_agent_status!(result, files, store, state)
      require_nonempty_artifact!(files.super_fix_result_path(iteration), 'Pi super-review fix/adjudication')
      resolutions = result.data.fetch('resolutions', [])
      findings = Array(state.fetch('final_super_review_findings', [])) + Array(state['super_review_fix_review_findings'])
      validate_resolution_coverage!(findings.uniq { |finding| finding.fetch('id') }, resolutions)
      needs_user = resolutions.select { |resolution| resolution['decision'] == 'needs_user' }
      pause_for_needs_user!(needs_user, files, store, state) unless needs_user.empty?
      state['super_review_fix_resolutions'] = resolutions
      state['super_review_fix_followups'] = Array(result.data['followups'])
      state['phase'] = 'ready_to_commit_super_review_fix'
      state['next_action'] = 'commit_super_review_fix'
      store.write(state)
      commit_super_review_fix(context, repo, files, config, store, state)
    end

    def commit_super_review_fix(context, repo, files, config, store, state)
      iteration = state.fetch('super_review_fix_iteration')
      accepted = accepted_resolutions(Array(state['super_review_fix_resolutions']))
      if repo.clean?
        if accepted.empty?
          state['pending_super_review_fix_review'] = true
          state['phase'] = 'ready_to_send_claude_super_review_fix_review'
          state['next_action'] = 'send_claude_super_review_fix_review_prompt'
          store.write(state)
          send_claude_super_review_fix_review(context, repo, files, config, store, state)
          return
        end

        pause_with_reason!(files, store, state, "Pi accepted super-review finding(s) in fix #{iteration}, but the worktree is clean. See #{files.super_fix_result_path(iteration)}")
      end

      ensure_commit_budget!(files, store, state, config)
      repo.add_all
      commit_sha = repo.commit("Super-review fix #{iteration}")
      raise Error, "Worktree is dirty after super-review fix #{iteration} commit:\n#{repo.status}" unless repo.clean?

      state['super_review_fix_commits'] = super_review_fix_commits(state) + [commit_sha]
      state['last_commit'] = commit_sha
      state['pending_super_review_fix_review'] = true
      state.delete('super_review_fix_review_findings')
      state['phase'] = 'ready_to_run_final_checks'
      state['next_action'] = 'run_final_checks_after_super_review_fix'
      store.write(state)
      puts "Committed super-review fix #{iteration}: #{commit_sha}"
      run_final_checks(context, repo, files, config, store, state)
    end

    def send_claude_super_review_fix_review(context, repo, files, config, store, state)
      raise Error, "Refusing to send Claude super-review fix review with dirty worktree in #{repo.root}:\n#{repo.status}" unless repo.clean?

      iteration = state.fetch('super_review_fix_iteration')
      commits = super_review_fix_commits(state)
      prompt = PromptWriter.new(files, context, repo).claude_super_review_fix_review(iteration, commits)
      @tmux.send_prompt(config.fetch('claude_worker_target'), prompt)
      state['status'] = 'running'
      state['phase'] = 'waiting_for_claude_super_review_fix_review'
      state['next_action'] = 'wait_for_claude_super_review_fix_review_status'
      store.write(state)
      puts "Sent super-review fix review #{iteration} prompt to claude-worker: #{prompt}"
      wait_for_claude_super_review_fix_review(context, repo, files, config, store, state)
    end

    def wait_for_claude_super_review_fix_review(context, repo, files, config, store, state)
      iteration = state.fetch('super_review_fix_iteration')
      result = wait_for_status(files.status_path(0, 'claude', 'super_fix_review', iteration), expected: { agent: 'claude', phase: 'super_fix_review', step: 0 }, config: config)
      handle_agent_status!(result, files, store, state)
      require_nonempty_artifact!(files.super_fix_review_path(iteration), 'Claude super-review fix review')
      raise Error, "Claude super-review fix review changed repo files; worktree must remain clean:\n#{repo.status}" unless repo.clean?

      findings = actionable_findings(result.data)
      state['super_review_fix_reviews'] = Array(state['super_review_fix_reviews']) + [{
        'iteration' => iteration,
        'status' => 'done',
        'summary' => result.data['summary'],
        'findings_count' => findings.count
      }]
      if findings.empty?
        state['final_super_reviewed'] = true
        state.delete('pending_super_review_fix_review')
        state.delete('super_review_fix_review_findings')
        store.write(state)
        complete_run(context, repo, files, store, state, state.fetch('final_checks'))
      else
        state['super_review_fix_review_findings'] = findings
        state.delete('pending_super_review_fix_review')
        state['phase'] = 'ready_to_send_pi_super_review_fix'
        state['next_action'] = 'send_pi_super_review_fix_prompt'
        store.write(state)
        send_pi_super_review_fix(context, repo, files, config, store, state)
      end
    end

    def super_review_fix_commits(state)
      Array(state['super_review_fix_commits'])
    end

    def send_pi_manager_fix(context, repo, files, config, store, state)
      raise Error, "Refusing to send Pi manager fix with dirty baseline in #{repo.root}:\n#{repo.status}" unless repo.clean?

      iteration = (state['manager_fix_iteration'] || 0) + 1
      if iteration > config.fetch('max_manager_review_fix_iterations', 5).to_i
        pause_with_reason!(files, store, state, "Manager findings still need work after #{iteration - 1} fix iteration(s). See #{files.manager_review_path}")
      end

      prompt = PromptWriter.new(files, context, repo).pi_manager_fix(
        iteration,
        state.fetch('manager_review_iteration'),
        state.fetch('manager_review_findings'),
        state['manager_fix_review_findings']
      )
      @tmux.send_prompt(config.fetch('pi_worker_target'), prompt)
      state['status'] = 'running'
      state['manager_fix_iteration'] = iteration
      state['phase'] = 'waiting_for_pi_manager_fix'
      state['next_action'] = 'wait_for_pi_manager_fix_status'
      store.write(state)
      puts "Sent manager fix #{iteration} prompt to pi-worker: #{prompt}"
      wait_for_pi_manager_fix(context, repo, files, config, store, state)
    end

    def wait_for_pi_manager_fix(context, repo, files, config, store, state)
      iteration = state.fetch('manager_fix_iteration')
      result = wait_for_status(
        files.status_path(0, 'pi', 'manager_fix', iteration),
        expected: { agent: 'pi', phase: 'manager_fix', step: 0 },
        config: config
      )
      handle_agent_status!(result, files, store, state)
      require_nonempty_artifact!(files.manager_fix_result_path(iteration), 'Pi manager fix report')
      state['manager_fix_followups'] = (Array(state['manager_fix_followups']) + Array(result.data['followups'])).uniq
      state['phase'] = 'ready_to_commit_manager_fix'
      state['next_action'] = 'commit_manager_fix'
      store.write(state)
      commit_manager_fix(context, repo, files, config, store, state)
    end

    def commit_manager_fix(context, repo, files, config, store, state)
      iteration = state.fetch('manager_fix_iteration')
      if repo.clean?
        pause_with_reason!(files, store, state, "Pi manager fix #{iteration} produced no repo changes. See #{files.manager_fix_result_path(iteration)}")
      end

      ensure_commit_budget!(files, store, state, config)
      repo.add_all
      commit_sha = repo.commit("Manager review fix #{iteration}")
      raise Error, "Worktree is dirty after manager fix #{iteration} commit:\n#{repo.status}" unless repo.clean?

      state['manager_fix_commits'] = manager_fix_commits(state) + [commit_sha]
      state['last_commit'] = commit_sha
      state['pending_manager_fix_review'] = true
      state.delete('manager_fix_review_findings')
      state['phase'] = 'ready_to_run_final_checks'
      state['next_action'] = 'run_final_checks_after_manager_fix'
      store.write(state)
      puts "Committed manager review fix #{iteration}: #{commit_sha}"
      run_final_checks(context, repo, files, config, store, state)
    end

    def send_claude_manager_fix_review(context, repo, files, config, store, state)
      raise Error, "Refusing to send Claude manager-fix review with dirty worktree in #{repo.root}:\n#{repo.status}" unless repo.clean?

      iteration = state.fetch('manager_fix_iteration')
      commit_sha = manager_fix_commits(state).last
      raise Error, 'Manager-fix review requires a manager-fix commit' if commit_sha.to_s.empty?

      prompt = PromptWriter.new(files, context, repo).claude_manager_fix_review(
        iteration,
        state.fetch('manager_review_iteration'),
        commit_sha,
        state.fetch('manager_review_findings')
      )
      @tmux.send_prompt(config.fetch('claude_worker_target'), prompt)
      state['status'] = 'running'
      state['phase'] = 'waiting_for_claude_manager_fix_review'
      state['next_action'] = 'wait_for_claude_manager_fix_review_status'
      store.write(state)
      puts "Sent manager-fix review #{iteration} prompt to claude-worker: #{prompt}"
      wait_for_claude_manager_fix_review(context, repo, files, config, store, state)
    end

    def wait_for_claude_manager_fix_review(context, repo, files, config, store, state)
      iteration = state.fetch('manager_fix_iteration')
      result = wait_for_status(
        files.status_path(0, 'claude', 'manager_fix_review', iteration),
        expected: { agent: 'claude', phase: 'manager_fix_review', step: 0 },
        config: config
      )
      handle_agent_status!(result, files, store, state)
      require_nonempty_artifact!(files.manager_fix_review_path(iteration), 'Claude manager-fix review')
      raise Error, "Claude manager-fix review changed repo files; worktree must remain clean:\n#{repo.status}" unless repo.clean?

      findings = actionable_findings(result.data)
      state['manager_fix_reviews'] = Array(state['manager_fix_reviews']) + [{
        'iteration' => iteration,
        'status' => 'done',
        'summary' => result.data['summary'],
        'findings_count' => findings.count
      }]
      if findings.empty?
        state.delete('pending_manager_fix_review')
        state.delete('manager_fix_review_findings')
        state['manager_review_cycles'].last['status'] = 'fixed_and_reviewed' if Array(state['manager_review_cycles']).last
        store.write(state)
        complete_run(context, repo, files, store, state, state.fetch('final_checks'))
      else
        state['manager_fix_review_findings'] = findings
        state.delete('pending_manager_fix_review')
        state['phase'] = 'ready_to_send_pi_manager_fix'
        state['next_action'] = 'send_pi_manager_fix_prompt'
        store.write(state)
        send_pi_manager_fix(context, repo, files, config, store, state)
      end
    end

    def manager_fix_commits(state)
      Array(state['manager_fix_commits'])
    end

    def complete_run(context, repo, files, store, state, results)
      return mark_complete_after_manager_review(context, repo, files, store, state, results) if state['manager_context_reviewed']

      FileUtils.rm_f(files.paused_reason_path)
      state.delete('paused_reason')
      state['status'] = 'manager_review'
      state['phase'] = 'ready_for_manager_final_review'
      state['next_action'] = 'manager_context_production_readiness_review'
      state['manager_review_iteration'] = (state['manager_review_iteration'] || 0) + 1
      state['final_summary'] = files.final_summary_path
      state['manager_review'] = files.manager_review_path
      store.write(state)
      write_final_summary(context, repo, files, state, results)
      write_manager_review_request(context, repo, files, state)
      print_manager_final_review_instructions(repo, files, state)
    end

    def mark_complete_after_manager_review(context, repo, files, store, state, results)
      FileUtils.rm_f(files.paused_reason_path)
      state.delete('paused_reason')
      state['status'] = 'done'
      state['phase'] = 'complete'
      state['next_action'] = 'none'
      state['final_summary'] = files.final_summary_path
      store.write(state)
      write_final_summary(context, repo, files, state, results)
      puts "/autowork complete. Production-readiness manager review passed."
      puts "- summary: #{files.final_summary_path}"
      puts "- manager review: #{files.manager_review_path}"
      puts "- repo: #{repo.root}"
    end

    def print_manager_final_review_instructions(repo, files, state)
      iteration = state.fetch('manager_review_iteration')
      puts "/autowork reached final manager-context production-readiness review #{iteration}."
      puts "Use the pi-manager conversation context that pi-worker and claude-worker did not have."
      puts "Read:"
      puts "- manager review checklist: #{files.manager_review_path}"
      puts "- summary: #{files.final_summary_path}"
      puts "- final checks: #{files.final_checks_path}"
      puts "- super-review: #{files.super_review_path}"
      puts "- repo: #{repo.root}"
      puts "If clean, run: autowork manager-review-pass #{files.task_folder}"
      puts "If findings exist, write: #{files.manager_findings_path(iteration)}"
      puts "Then route automatically: autowork manager-review-fix #{files.task_folder}"
    end

    def write_manager_review_request(context, repo, files, state)
      iteration = state.fetch('manager_review_iteration')
      text = <<~MD
        # Manager-context production-readiness review

        Before declaring `/autowork` complete, pi-manager must perform this final review using the full context available only in the manager conversation: original user request, draft/task creation, grilling decisions, task edits, scope boundaries, explicit user preferences, and any caveats that may not be fully captured in `task.md` or `steps.md`.

        Assume `pi-worker` and `claude-worker` may have missed important intent/context because they only saw task artifacts and prompts.

        ## Read

        - task: #{File.join(context.task_folder, 'task.md')}
        - steps: #{File.join(context.task_folder, 'steps.md')}
        - final summary: #{files.final_summary_path}
        - final checks: #{files.final_checks_path}
        - final super-review: #{files.super_review_path}
        - super-review fix artifacts: #{File.join(files.log_dir, 'super_fixes')}
        - repo: #{repo.root}

        ## Check

        - Does the final implementation satisfy the original user intent, not just `steps.md`?
        - Did the work accidentally expand or shrink scope?
        - Did any grilling/task decision get lost?
        - Did Pi or Claude reject/accept a finding contrary to manager-only context?
        - Are follow-ups acceptable and clearly surfaced?
        - Is anything important missing from `final_summary.md`?
        - Is the result production-ready if the user does not perform another review?

        If this review finds anything that would make the change unsafe, incomplete, misleading, under-tested, over-scoped, or not production-ready, do not mark complete. Write structured findings to:

        ```text
        #{files.manager_findings_path(iteration)}
        ```

        Required JSON shape:

        ```json
        {
          "summary": "Why manager review did not pass",
          "findings": [
            {
              "id": "MR1",
              "severity": "BLOCKER",
              "title": "Short title",
              "body": "What is wrong and why it matters",
              "recommendation": "Concrete required fix"
            }
          ],
          "followups": []
        }
        ```

        Use `BLOCKER` for production correctness/safety gaps and `MINOR` for local low-risk fixes. Include every actionable finding in one pass. Then run:

        ```sh
        autowork manager-review-fix #{files.task_folder}
        ```

        That command owns Pi routing, commits, full checks, scoped Claude review, retries, and return to a fresh manager gate. Do not send manual tmux prompts or create manual commits.

        If clean, record your pass below and run:

        ```sh
        autowork manager-review-pass #{files.task_folder}
        ```

        ## Manager review result

        - Review iteration: #{iteration}
        - Pending.
      MD
      File.write(files.manager_review_path, text)
      File.write(files.manager_review_iteration_path(iteration), text)
    end

    def send_pi_final_check_fix(context, repo, files, config, store, state)
      raise Error, "Refusing to send Pi final-check fix with dirty baseline in #{repo.root}:\n#{repo.status}" unless repo.clean?

      iteration = (state['final_check_fix_iteration'] || 0) + 1
      if iteration > config.fetch('max_final_check_fix_iterations', 5).to_i
        pause_with_reason!(files, store, state, "Final checks still fail after #{iteration - 1} fix iteration(s). See #{files.final_checks_path}")
      end
      prompt = PromptWriter.new(files, context, repo).pi_final_check_fix(iteration, state.fetch('final_checks', []), state['final_check_review_findings'])
      @tmux.send_prompt(config.fetch('pi_worker_target'), prompt)
      state['status'] = 'running'
      state['final_check_fix_iteration'] = iteration
      state['phase'] = 'waiting_for_pi_final_check_fix'
      state['next_action'] = 'wait_for_pi_final_check_fix_status'
      store.write(state)
      puts "Sent final-check fix #{iteration} prompt to pi-worker: #{prompt}"
      wait_for_pi_final_check_fix(context, repo, files, config, store, state)
    end

    def wait_for_pi_final_check_fix(context, repo, files, config, store, state)
      iteration = state.fetch('final_check_fix_iteration')
      result = wait_for_status(files.status_path(0, 'pi', 'final_checks_fix', iteration), expected: { agent: 'pi', phase: 'final_checks', step: 0 }, config: config)
      handle_agent_status!(result, files, store, state)
      state['phase'] = 'ready_to_commit_final_check_fix'
      state['next_action'] = 'commit_final_check_fix'
      store.write(state)
      commit_final_check_fix(context, repo, files, config, store, state)
    end

    def commit_final_check_fix(context, repo, files, config, store, state)
      iteration = state.fetch('final_check_fix_iteration')
      if repo.clean?
        state['phase'] = 'ready_to_run_final_checks'
        state['next_action'] = 'run_final_checks'
        store.write(state)
        puts "Final-check fix #{iteration} produced no repo changes; rerunning final checks."
        run_final_checks(context, repo, files, config, store, state)
        return
      end

      ensure_commit_budget!(files, store, state, config)
      repo.add_all
      commit_sha = repo.commit("Final checks fix #{iteration}")
      raise Error, "Worktree is dirty after final-check fix #{iteration} commit:\n#{repo.status}" unless repo.clean?

      state['final_check_fix_commits'] = final_check_fix_commits(state) + [commit_sha]
      state['last_commit'] = commit_sha
      state.delete('final_check_review_findings')
      state.delete('final_check_reviewed')
      state['phase'] = 'ready_to_run_final_checks'
      state['next_action'] = 'run_final_checks'
      store.write(state)
      puts "Committed final-check fix #{iteration}: #{commit_sha}"
      run_final_checks(context, repo, files, config, store, state)
    end

    def send_claude_final_check_review(context, repo, files, config, store, state)
      raise Error, "Refusing to send Claude final-check review with dirty worktree in #{repo.root}:\n#{repo.status}" unless repo.clean?

      review = (state['final_check_review_iteration'] || 0) + 1
      prompt = PromptWriter.new(files, context, repo).claude_final_check_review(review, final_check_fix_commits(state))
      @tmux.send_prompt(config.fetch('claude_worker_target'), prompt)
      state['status'] = 'running'
      state['final_check_review_iteration'] = review
      state['phase'] = 'waiting_for_claude_final_check_review'
      state['next_action'] = 'wait_for_claude_final_check_review_status'
      store.write(state)
      puts "Sent final-check review #{review} prompt to claude-worker: #{prompt}"
      wait_for_claude_final_check_review(context, repo, files, config, store, state)
    end

    def wait_for_claude_final_check_review(context, repo, files, config, store, state)
      review = state.fetch('final_check_review_iteration')
      result = wait_for_status(files.status_path(0, 'claude', 'final_checks_review', review), expected: { agent: 'claude', phase: 'final_checks', step: 0 }, config: config)
      handle_agent_status!(result, files, store, state)
      require_nonempty_artifact!(files.final_check_review_path(review), 'Claude final-check review')
      raise Error, "Claude final-check review changed repo files; worktree must remain clean:\n#{repo.status}" unless repo.clean?

      findings = actionable_findings(result.data)
      state['final_check_reviews'] = Array(state['final_check_reviews']) + [{
        'iteration' => review,
        'status' => 'done',
        'summary' => result.data['summary'],
        'findings_count' => findings.count
      }]
      if findings.empty?
        state['final_check_reviewed'] = true
        store.write(state)
        continue_after_passing_final_checks(context, repo, files, config, store, state, state.fetch('final_checks'))
      else
        state['final_check_review_findings'] = findings
        state['phase'] = 'ready_to_send_pi_final_check_fix'
        state['next_action'] = 'send_pi_final_check_fix_prompt'
        store.write(state)
        send_pi_final_check_fix(context, repo, files, config, store, state)
      end
    end

    def final_check_fix_commits(state)
      Array(state['final_check_fix_commits'])
    end

    def skipped_final_check_results
      [{
        'command' => nil,
        'status' => 'skipped',
        'summary' => 'No final_check_commands configured. Ruby checks are configured automatically only when Gemfile exists.'
      }]
    end

    def compact_final_check_results(results)
      results.map { |result| compact_final_check_result(result) }
    end

    def compact_final_check_result(result)
      return result.dup if result.fetch('status') == 'skipped'

      compact = {
        'command' => result.fetch('command'),
        'status' => result.fetch('status'),
        'exit_status' => result.fetch('exit_status')
      }
      stdout = result.fetch('stdout', '').to_s
      stderr = result.fetch('stderr', '').to_s
      compact['stdout_bytes'] = stdout.bytesize
      compact['stderr_bytes'] = stderr.bytesize
      compact['stdout_tail'] = tail_text(stdout) unless stdout.empty?
      compact['stderr_tail'] = tail_text(stderr) unless stderr.empty?
      compact
    end

    def tail_text(text, max_bytes = 4_000)
      return text if text.bytesize <= max_bytes

      "... output truncated; see autowork-log/final_checks.md for full output ...\n#{text.byteslice(-max_bytes, max_bytes)}"
    end

    def execute_final_check_commands(repo, commands)
      commands.map do |command|
        result = Shell.capture('bash', '-c', command, chdir: repo.root)
        {
          'command' => command,
          'status' => result.success? ? 'passed' : 'failed',
          'exit_status' => result.status.exitstatus,
          'stdout' => result.stdout,
          'stderr' => result.stderr
        }
      end
    end

    def write_final_checks(files, results)
      File.write(files.final_checks_path, <<~MD)
        # Final checks

        #{results.map { |result| final_check_result_markdown(result) }.join("\n")}
      MD
    end

    def final_check_result_markdown(result)
      if result.fetch('status') == 'skipped'
        return <<~MD
          ## skipped

          #{result.fetch('summary')}
        MD
      end

      <<~MD
        ## #{result.fetch('command')}

        Status: #{result.fetch('status')}
        Exit status: #{result.fetch('exit_status')}

        ### stdout

        ```text
        #{result.fetch('stdout')}
        ```

        ### stderr

        ```text
        #{result.fetch('stderr')}
        ```
      MD
    end

    def write_final_summary(context, repo, files, state, final_checks)
      File.write(files.final_summary_path, <<~MD)
        # Autowork final summary

        - Task: #{context.task_folder}
        - Repo: #{repo.root}
        - Final status: #{state.fetch('status', 'unknown')}
        - Final phase: #{state.fetch('phase', 'unknown')}

        ## Steps completed

        #{summary_steps_markdown(state)}

        ## Commits created

        #{summary_commits_markdown(state)}

        ## Reviews and outcomes

        #{summary_reviews_markdown(state)}

        ## Debates and final decisions

        #{summary_debates_markdown(files)}

        ## Final checks

        #{summary_final_checks_markdown(final_checks)}

        ## Final super-review

        #{summary_super_review_markdown(files, state)}

        ## Manager review loop

        #{summary_manager_review_markdown(state)}

        ## Review follow-ups

        #{summary_review_followups_markdown(state)}

        ## Super-review follow-ups

        #{summary_super_review_followups_markdown(state)}

        ## Unresolved caveats

        #{summary_unresolved_caveats_markdown(state)}
      MD
    end

    def summary_steps_markdown(state)
      state.fetch('steps').map do |number, data|
        "- Step #{number}: #{data.fetch('status')}"
      end.join("\n")
    end

    def summary_commits_markdown(state)
      step_commits = state.fetch('steps').flat_map do |number, data|
        data.fetch('commits').map { |sha| "- Step #{number}: #{sha}" }
      end
      final_commits = final_check_fix_commits(state).each_with_index.map do |sha, index|
        "- Final checks fix #{index + 1}: #{sha}"
      end
      super_commits = super_review_fix_commits(state).each_with_index.map do |sha, index|
        "- Super-review fix #{index + 1}: #{sha}"
      end
      manager_commits = manager_fix_commits(state).each_with_index.map do |sha, index|
        "- Manager review fix #{index + 1}: #{sha}"
      end
      (step_commits + final_commits + super_commits + manager_commits).join("\n")
    end

    def summary_reviews_markdown(state)
      step_reviews = state.fetch('steps').flat_map do |number, data|
        data.fetch('reviews').map do |review|
          "- Step #{number} review #{review.fetch('iteration')}: #{review.fetch('summary')}"
        end
      end
      final_reviews = Array(state['final_check_reviews']).map do |review|
        "- Final checks review #{review.fetch('iteration')}: #{review.fetch('summary')}"
      end
      super_reviews = Array(state['super_review_fix_reviews']).map do |review|
        "- Super-review fix review #{review.fetch('iteration')}: #{review.fetch('summary')}"
      end
      manager_reviews = Array(state['manager_fix_reviews']).map do |review|
        "- Manager review fix review #{review.fetch('iteration')}: #{review.fetch('summary')}"
      end
      (step_reviews + final_reviews + super_reviews + manager_reviews).join("\n")
    end

    def summary_debates_markdown(files)
      debates = Dir.glob(File.join(files.log_dir, 'debates', '*.md')).sort
      return '- None.' if debates.empty?

      debates.map { |path| "- #{path}" }.join("\n")
    end

    def summary_final_checks_markdown(final_checks)
      final_checks.map do |result|
        label = result['command'] || 'no configured command'
        "- #{label}: #{result.fetch('status')}"
      end.join("\n")
    end

    def summary_super_review_markdown(files, state)
      return '- Disabled by config.' unless state['final_super_reviewed']

      lines = ["- Report: #{files.super_review_path}"]
      lines << "- Initial report: #{state['final_super_review_summary']}" if state['final_super_review_summary']
      lines << "- Fix commits: #{super_review_fix_commits(state).count}"
      lines << '- Final outcome: accepted.'
      lines.join("\n")
    end

    def summary_manager_review_markdown(state)
      cycles = Array(state['manager_review_cycles'])
      return "- Awaiting manager review iteration #{state['manager_review_iteration'] || 1}." if cycles.empty?

      cycles.map do |cycle|
        "- Review #{cycle.fetch('iteration')}: #{cycle.fetch('status')} — #{cycle.fetch('summary')} (#{cycle.fetch('findings_count')} finding(s))"
      end.join("\n")
    end

    def summary_review_followups_markdown(state)
      followups = Array(state['step_review_followups'])
      return '- None.' if followups.empty?

      followups.map { |followup| "- #{followup}" }.join("\n")
    end

    def summary_super_review_followups_markdown(state)
      followups = super_review_followups(state)
      return '- None.' if followups.empty?

      followups.map { |followup| "- #{followup}" }.join("\n")
    end

    def super_review_followups(state)
      (Array(state['final_super_review_followups']) + Array(state['super_review_fix_followups']) + Array(state['super_review_followups'])).uniq
    end

    def summary_unresolved_caveats_markdown(state)
      caveats = []
      caveats << state['paused_reason'] if state['paused_reason']
      caveats.concat(Array(state['step_review_followups']))
      caveats.concat(super_review_followups(state))
      caveats.concat(Array(state['manager_review_followups']))
      caveats.concat(Array(state['manager_fix_followups']))
      caveats.uniq!
      return '- None.' if caveats.empty?

      caveats.map { |caveat| "- #{caveat}" }.join("\n")
    end

    def wait_for_status(path, expected:, config:, timeout_seconds: nil)
      validator = StatusValidator.new
      deadline = Time.now + (timeout_seconds || worker_status_timeout_seconds(config))
      last_invalid_result = nil
      loop do
        result = validator.validate_file(path, expected: expected)
        return result if result.valid?

        last_invalid_result = result if File.file?(path)
        break if Time.now >= deadline

        @sleeper.call(1)
      end
      if last_invalid_result
        raise Error, "Invalid status JSON at #{path}: #{last_invalid_result.errors.join('; ')}"
      end
      raise Error, "Worker status timeout while waiting for status JSON: #{path}\nUse `autowork status <task_folder>` or inspect autowork-log/state.json for read-only status. Rerunning `/autowork` resumes orchestration and may stage/commit if the worker has finished. If the manager process was killed by an outer shell/tool timeout, do not rerun automatically; ask the operator for a fresh explicit continue/resume instruction."
    end

    def require_nonempty_artifact!(path, label)
      return if File.file?(path) && !File.read(path).strip.empty?

      raise Error, "#{label} artifact is missing or empty: #{path}. Agents must write artifacts before status JSON."
    end

    def handle_agent_status!(result, files, store, state)
      return if result.data['status'] == 'done'

      pause_with_reason!(files, store, state, "Agent reported #{result.data['status']}: #{result.data['summary']}")
    end

    def actionable_findings(status_data)
      Array(status_data['findings']).select { |finding| %w[BLOCKER MINOR].include?(finding['severity']) }
    end

    def super_review_findings(status_data)
      Array(status_data['findings']).select { |finding| %w[BLOCKER MINOR CRITICAL HIGH MEDIUM].include?(finding['severity']) }
    end

    def accepted_resolutions(resolutions)
      resolutions.select { |resolution| %w[accept accept_with_alternative_fix].include?(resolution['decision']) }
    end

    def follow_up_resolutions(resolutions)
      resolutions.select { |resolution| resolution['decision'] == 'follow_up' }
    end

    def unresolved_resolutions(resolutions)
      resolutions.select { |resolution| resolution['decision'] == 'dispute' }
    end

    def validate_resolution_coverage!(findings, resolutions)
      finding_ids = findings.map { |finding| finding.fetch('id') }
      resolution_ids = resolutions.map { |resolution| resolution.fetch('finding_id') }
      missing = finding_ids - resolution_ids
      unknown = resolution_ids - finding_ids
      raise Error, "Pi classification did not cover findings: #{missing.join(', ')}" unless missing.empty?
      raise Error, "Pi classification referenced unknown findings: #{unknown.join(', ')}" unless unknown.empty?
    end

    def validate_follow_up_severity!(findings, resolutions)
      findings_by_id = findings.to_h { |finding| [finding.fetch('id'), finding] }
      invalid = resolutions.select do |resolution|
        resolution['decision'] == 'follow_up' && findings_by_id.fetch(resolution.fetch('finding_id'))['severity'] == 'MINOR'
      end
      return if invalid.empty?

      ids = invalid.map { |resolution| resolution.fetch('finding_id') }.join(', ')
      raise Error, "MINOR findings must be fixed now, not recorded as follow-ups: #{ids}"
    end

    def record_step_review_followups(state, resolutions)
      state['step_review_followups'] ||= []
      resolutions.each do |resolution|
        state['step_review_followups'] << "#{resolution['finding_id']}: #{resolution['rationale']}"
      end
      state['step_review_followups'].uniq!
    end

    def ensure_commit_budget!(files, store, state, config)
      max_commits = Integer(config.fetch('max_total_commits', DEFAULT_MAX_TOTAL_COMMITS))
      current_commits = state.fetch('steps', {}).values.sum { |step| Array(step['commits']).count } +
        %w[final_check_fix_commits super_review_fix_commits manager_fix_commits].sum { |key| Array(state[key]).count }
      return if current_commits < max_commits

      pause_with_reason!(
        files,
        store,
        state,
        "Autowork commit limit reached: #{current_commits}/#{max_commits}. Increase max_total_commits explicitly before continuing."
      )
    end

    def pause_for_needs_user!(resolutions, files, store, state)
      details = resolutions.map { |resolution| "- #{resolution['finding_id']}: #{resolution['rationale']}" }.join("\n")
      pause_with_reason!(files, store, state, "Pi requested user input for review finding(s):\n#{details}")
    end

    def pause_for_unresolved!(resolutions, files, store, state)
      details = resolutions.map { |resolution| "- #{resolution['finding_id']} #{resolution['decision']}: #{resolution['rationale']}" }.join("\n")
      pause_with_reason!(files, store, state, "Review finding(s) need debate/user review before continuing:\n#{details}")
    end

    def pause_with_reason!(files, store, state, reason)
      state['status'] = 'paused'
      state['paused_reason'] = reason
      File.write(files.paused_reason_path, "# Autowork paused\n\n#{reason}\n")
      store.write(state)
      raise Error, reason
    end

    def record_unresolved_findings(files, state, resolutions)
      return if resolutions.empty?

      step = state['current_step']
      review = state['review_iteration'] || 1
      File.open(files.debate_path(step), 'a') do |file|
        file.puts "## Review #{review} unresolved findings"
        resolutions.each do |resolution|
          file.puts
          file.puts "### #{resolution['finding_id']} — #{resolution['decision']}"
          file.puts
          file.puts resolution['rationale']
        end
        file.puts
      end
    end

    def worker_status_timeout_seconds(config)
      return ENV.fetch('AUTOWORK_WORKER_STATUS_TIMEOUT_SECONDS').to_i if ENV.key?('AUTOWORK_WORKER_STATUS_TIMEOUT_SECONDS')
      return ENV.fetch('AUTOWORK_PROMPT_TIMEOUT_SECONDS').to_i if ENV.key?('AUTOWORK_PROMPT_TIMEOUT_SECONDS')

      config.fetch('worker_status_timeout_minutes', config.fetch('agent_prompt_timeout_minutes', 10)).to_i * 60
    end

    def super_review_status_timeout_seconds(config)
      return ENV.fetch('AUTOWORK_SUPER_REVIEW_STATUS_TIMEOUT_SECONDS').to_i if ENV.key?('AUTOWORK_SUPER_REVIEW_STATUS_TIMEOUT_SECONDS')

      config.fetch('super_review_status_timeout_minutes', 20).to_i * 60
    end
  end

  class Doctor
    def initialize(argv, tmux: Tmux.new, cwd: Dir.pwd)
      @argv = argv.dup
      @tmux = tmux
      @cwd = cwd
      remove_flag('--send-test')
      remove_flag('send-test')
      @is_send_test = !(remove_flag('--no-send-test') || remove_flag('no-send-test'))
    end

    def run
      raise Error, 'Usage: autowork doctor [--no-send-test]' unless @argv.empty?

      repo = safe_repo(@cwd)
      puts 'Autowork doctor'
      puts "helper: #{File.join(ROOT, 'bin', 'autowork')}"
      puts "repo_dir: #{repo&.root || @cwd}"
      puts "branch: #{repo ? repo.branch : 'unknown'}"
      puts "worktree: #{repo ? (repo.clean? ? 'clean' : 'dirty') : 'unknown'}"
      roles = report_panes(repo)
      report_prompt_delivery(roles)
      send_test(roles) if @is_send_test && roles
      report_status_validator
    end

    private

    def remove_flag(flag)
      removed = @argv.delete(flag)
      !removed.nil?
    end

    def safe_repo(path)
      GitRepo.new(path)
    rescue Error => e
      puts "repo_error: #{e.message}"
      nil
    end

    def report_panes(repo)
      roles = repo ? @tmux.discover_roles(repo.root) : nil
      if roles
        puts 'tmux_panes: ok'
        puts "pi-manager: #{roles.manager.id} #{roles.manager.path}"
        puts "pi-worker: #{roles.pi_worker.id} #{roles.pi_worker.path}"
        puts "claude-worker: #{roles.claude_worker.id} #{roles.claude_worker.path}"
      end
      roles
    rescue Error => e
      puts "tmux_panes: failed - #{e.message}"
      nil
    end

    def report_prompt_delivery(roles)
      if roles
        puts 'prompt_delivery: ready'
        if @is_send_test
          puts 'prompt_delivery_send_test: enabled'
        else
          puts 'prompt_delivery_send_test: skipped (--no-send-test)'
        end
      else
        puts 'prompt_delivery: blocked until tmux panes are healthy'
      end
    end

    def send_test(roles)
      message = "AUTOWORK DOCTOR SEND TEST #{Time.now.iso8601}: no action required"
      @tmux.send_text(roles.pi_worker.id, message)
      @tmux.send_text(roles.claude_worker.id, message)
      puts 'prompt_delivery_send_test: sent to pi-worker and claude-worker'
    end

    def report_status_validator
      sample = { 'status' => 'done', 'agent' => 'pi', 'phase' => 'implement', 'step' => 1, 'summary' => 'sample' }
      result = StatusValidator.new.validate_hash(sample, expected: { agent: 'pi', phase: 'implement', step: 1 })
      puts "status_json_validator: #{result.valid? ? 'ok' : "failed - #{result.errors.join('; ')}"}"
    end
  end

  class ManagerReviewFix
    def initialize(argv, tmux: Tmux.new)
      @argv = argv
      @tmux = tmux
    end

    def run
      task_folder = @argv&.first
      raise Error, 'Usage: autowork manager-review-fix <task_folder>' unless task_folder && @argv.length == 1

      files = RunFiles.new(task_folder)
      files.mkdirs
      lock = RunLock.new(files.lock_path)
      lock.acquire!
      begin
        config = YAML.safe_load(File.read(files.config_path))
        store = StateStore.new(files.state_path)
        state = store.read
        unless state['phase'] == 'ready_for_manager_final_review'
          raise Error, "Manager findings can only route from phase ready_for_manager_final_review, got #{state['phase'].inspect}"
        end

        repo = GitRepo.new(config.fetch('repo_dir'))
        raise Error, "Worktree must be clean before manager-review-fix:\n#{repo.status}" unless repo.clean?
        expected_branch = config['branch_name']
        if expected_branch && !expected_branch.empty? && repo.branch != expected_branch
          raise Error, "Manager findings belong to branch #{expected_branch.inspect}; current branch is #{repo.branch.inspect}"
        end

        review_iteration = state.fetch('manager_review_iteration', 1)
        findings_path = files.manager_findings_path(review_iteration)
        validation = ManagerFindingsValidator.new.validate_file(findings_path)
        raise Error, "Invalid manager findings JSON at #{findings_path}: #{validation.errors.join('; ')}" unless validation.valid?

        data = validation.data
        state['manager_review_findings'] = data.fetch('findings')
        state['manager_review_followups'] = (Array(state['manager_review_followups']) + Array(data['followups'])).uniq
        state['manager_review_cycles'] = Array(state['manager_review_cycles']) + [{
          'iteration' => review_iteration,
          'status' => 'routed_for_fix',
          'summary' => data.fetch('summary'),
          'findings_count' => data.fetch('findings').count,
          'findings_file' => findings_path
        }]
        state.delete('manager_fix_review_findings')
        state.delete('pending_manager_fix_review')
        state['status'] = 'running'
        state['phase'] = 'ready_to_send_pi_manager_fix'
        state['next_action'] = 'send_pi_manager_fix_prompt'
        store.write(state)
        mark_manager_review_routed(files, review_iteration, findings_path)
      ensure
        lock.release!
      end

      Orchestrator.new(orchestrator_args(config), tmux: @tmux).run
    end

    private

    def orchestrator_args(config)
      selector = project_selector(config.fetch('task_project'), config.fetch('repo_dir'))
      args = [selector, config.fetch('task_id').to_s]
      args << config.fetch('review_base_ref') if config['review_base_ref_is_explicit']
      args
    end

    def project_selector(project, repo_dir)
      return project if project == 'env'

      checkout = File.basename(repo_dir)
      number = checkout.to_s[/\A\d+/]
      return project unless number

      "#{project}#{number}"
    end

    def mark_manager_review_routed(files, iteration, findings_path)
      existing = File.file?(files.manager_review_path) ? File.read(files.manager_review_path) : "# Manager-context production-readiness review\n"
      replacement = "- Review #{iteration} findings routed automatically.\n- Findings: #{findings_path}"
      updated = existing.sub('- Pending.', replacement)
      updated = "#{existing}\n#{replacement}\n" if updated == existing
      File.write(files.manager_review_path, updated)
      File.write(files.manager_review_iteration_path(iteration), updated)
    end
  end

  class ManagerReviewPass
    def initialize(argv)
      @argv = argv
    end

    def run
      task_folder = @argv&.first
      raise Error, 'Usage: autowork manager-review-pass <task_folder>' unless task_folder && @argv.length == 1

      files = RunFiles.new(task_folder)
      config = YAML.safe_load(File.read(files.config_path))
      repo = GitRepo.new(config.fetch('repo_dir'))
      raise Error, "Worktree must be clean before manager-review-pass:\n#{repo.status}" unless repo.clean?
      expected_branch = config['branch_name']
      if expected_branch && !expected_branch.empty? && repo.branch != expected_branch
        raise Error, "Manager review belongs to branch #{expected_branch.inspect}; current branch is #{repo.branch.inspect}"
      end

      store = StateStore.new(files.state_path)
      state = store.read
      unless state['phase'] == 'ready_for_manager_final_review'
        raise Error, "Manager review can only pass from phase ready_for_manager_final_review, got #{state['phase'].inspect}"
      end

      state['manager_context_reviewed'] = true
      state['manager_context_reviewed_at'] = Time.now.iso8601
      state['manager_review_passed_iteration'] = state.fetch('manager_review_iteration', 1)
      state['status'] = 'done'
      state['phase'] = 'complete'
      state['next_action'] = 'none'
      state['final_summary'] = files.final_summary_path
      store.write(state)
      mark_manager_review_passed(files, state)
      mark_final_summary_done(files, state)
      puts '/autowork complete. Production-readiness manager review passed.'
      puts "- summary: #{files.final_summary_path}"
      puts "- manager review: #{files.manager_review_path}"
    end

    private

    def mark_manager_review_passed(files, state)
      existing = File.file?(files.manager_review_path) ? File.read(files.manager_review_path) : "# Manager-context production-readiness review\n"
      updated = existing.sub('- Pending.', "- Passed at #{state['manager_context_reviewed_at']}.\n- Result: production-ready if the user does not perform another review.")
      updated = existing + "\n- Passed at #{state['manager_context_reviewed_at']}.\n" if updated == existing && !existing.include?(state['manager_context_reviewed_at'])
      File.write(files.manager_review_path, updated)
      File.write(files.manager_review_iteration_path(state.fetch('manager_review_passed_iteration')), updated)
    end

    def mark_final_summary_done(files, state)
      return unless File.file?(files.final_summary_path)

      text = File.read(files.final_summary_path)
      text = text.sub(/- Final status: .*/, '- Final status: done')
      text = text.sub(/- Final phase: .*/, '- Final phase: complete')
      text = text.sub(/- Awaiting manager review iteration \d+\./, "- Review #{state.fetch('manager_review_passed_iteration')}: passed.")
      marker = "\n## Manager-context production-readiness review\n\n- Passed.\n"
      text += marker unless text.include?('## Manager-context production-readiness review')
      File.write(files.final_summary_path, text)
    end
  end

  class BaseRebaser
    def initialize(argv, cwd: Dir.pwd)
      @argv = argv
      @cwd = cwd
    end

    def run
      requested_target_base_ref = parse_target_base_ref
      context = TaskResolver.new([], cwd: @cwd).resolve
      files = RunFiles.new(context.task_folder)
      raise Error, "Missing autowork config: #{files.config_path}" unless File.file?(files.config_path)
      raise Error, "Autowork run is active; stop it before rebasing: #{files.lock_path}" if File.file?(files.lock_path)

      config = YAML.safe_load(File.read(files.config_path))
      repo = GitRepo.new(config.fetch('repo_dir'))
      expected_branch = config['branch_name'].to_s.empty? ? repo.branch : config['branch_name']
      raise Error, "Run from the task branch #{expected_branch.inspect}; current branch is #{repo.branch.inspect}" unless repo.branch == expected_branch
      raise Error, "Worktree must be clean before rebase-base:\n#{repo.status}" unless repo.clean?

      old_base_ref = config.fetch('review_base_ref')
      old_base_commit = config['review_base_commit']
      raise Error, 'Missing review_base_commit; cannot safely determine which commits belong to this task' if old_base_commit.to_s.empty?

      repo.fetch_origin
      target_base_ref = resolve_target_base_ref(repo, requested_target_base_ref || old_base_ref)
      target_base_commit = repo.ref_commit(target_base_ref)
      unless repo.ancestor?(old_base_commit, 'HEAD')
        raise Error, "Recorded review_base_commit #{old_base_commit} is not an ancestor of HEAD; stop and inspect branch history before rebasing"
      end

      result = repo.rebase_onto(target_base_ref, old_base_commit)
      unless result.success?
        write_conflict_report(files, config, old_base_ref, old_base_commit, target_base_ref, result, repo)
        raise Error, "Rebase stopped with conflicts or errors. Resolve them, then finish the rebase manually. Conflict report: #{files.rebase_conflicts_path}"
      end

      update_base_metadata(files, config, repo, expected_branch, old_base_ref, old_base_commit, target_base_ref, target_base_commit)

      puts 'Rebased autowork branch onto review base.'
      puts "- task: #{context.task_folder}"
      puts "- branch: #{expected_branch}"
      puts "- old_review_base_ref: #{old_base_ref}"
      puts "- old_review_base_commit: #{old_base_commit}"
      puts "- review_base_ref: #{target_base_ref}"
      puts "- review_base_commit: #{target_base_commit}"
      puts '- push: not performed'
      puts '- next: run /autowork again only when you want to resume orchestration'
    end

    private

    def parse_target_base_ref
      return nil if @argv.empty?
      return @argv[0] if @argv.length == 1 && !@argv[0].to_s.empty? && !@argv[0].start_with?('-')

      raise Error, 'Usage: autowork rebase-base [base-ref]'
    end

    def resolve_target_base_ref(repo, base_ref)
      case base_ref
      when 'master'
        repo.ref_exists?('origin/master') ? 'origin/master' : 'master'
      when 'main'
        repo.ref_exists?('origin/main') ? 'origin/main' : 'main'
      else
        base_ref
      end
    end

    def update_base_metadata(files, config, repo, expected_branch, old_base_ref, old_base_commit, target_base_ref, target_base_commit)
      now = Time.now.iso8601
      config['branch_name'] = expected_branch
      config['original_review_base_ref'] ||= config['review_base_ref'] || old_base_ref
      config['original_review_base_commit'] ||= config['review_base_commit'] || old_base_commit
      config['review_base_ref'] = target_base_ref
      config['review_base_ref_is_explicit'] = true
      config['review_base_commit'] = target_base_commit
      config['review_base_recorded_at'] = now
      config['review_base_updated_at'] = now
      File.write(files.config_path, config.to_yaml)

      store = StateStore.new(files.state_path)
      state = store.read
      state['original_review_base_ref'] ||= config['original_review_base_ref']
      state['original_review_base_commit'] ||= config['original_review_base_commit']
      state['review_base_ref'] = target_base_ref
      state['review_base_commit'] = target_base_commit
      state['review_base_updated_at'] = now
      state.delete('paused_reason')
      state['status'] = 'running' if state['status'] == 'paused'
      store.write(state)
      FileUtils.rm_f(files.paused_reason_path)
      FileUtils.rm_f(files.rebase_conflicts_path)
      raise Error, 'Rebase completed but new review base is not an ancestor of HEAD; inspect branch history before resuming' unless repo.ancestor?(target_base_commit, 'HEAD')
    end

    def write_conflict_report(files, config, old_base_ref, old_base_commit, target_base_ref, result, repo)
      files.mkdirs
      files_with_conflicts = repo.unmerged_files
      conflict_sections = files_with_conflicts.map do |path|
        <<~MD
          ## #{path}

          - conflict: unresolved rebase conflict
          - kept side: unresolved
          - reason: unresolved
          - checks: not run; rebase is unresolved
        MD
      end.join("\n")
      conflict_sections = "- No unmerged files reported by Git. Inspect the rebase error output.\n" if conflict_sections.empty?

      File.write(files.rebase_conflicts_path, <<~MD)
        # Autowork rebase conflicts

        - branch: #{config['branch_name']}
        - old_review_base_ref: #{old_base_ref}
        - old_review_base_commit: #{old_base_commit}
        - target_review_base_ref: #{target_base_ref}

        ## Git output

        ```text
        #{result.stderr.empty? ? result.stdout : result.stderr}
        ```

        #{conflict_sections}
      MD
    end
  end

  class BaseRefUpdater
    def initialize(argv)
      @argv = argv
    end

    def run
      task_folder, new_base_ref = @argv
      raise Error, 'Usage: autowork update-base <task_folder> <new-base-ref>' unless task_folder && new_base_ref && @argv.length == 2

      files = RunFiles.new(task_folder)
      config = YAML.safe_load(File.read(files.config_path))
      repo = GitRepo.new(config.fetch('repo_dir'))
      new_base_commit = repo.ref_commit(new_base_ref)
      state = StateStore.new(files.state_path).read

      config['original_review_base_ref'] ||= config['review_base_ref']
      config['original_review_base_commit'] ||= config['review_base_commit']
      state['original_review_base_ref'] ||= config['original_review_base_ref']
      state['original_review_base_commit'] ||= config['original_review_base_commit']

      config['review_base_ref'] = new_base_ref
      config['review_base_ref_is_explicit'] = true
      config['review_base_commit'] = new_base_commit
      config['review_base_recorded_at'] = Time.now.iso8601
      File.write(files.config_path, config.to_yaml)

      state['review_base_ref'] = new_base_ref
      state['review_base_commit'] = new_base_commit
      state['review_base_updated_at'] = Time.now.iso8601
      state.delete('paused_reason')
      state['status'] = 'running' if state['status'] == 'paused'
      StateStore.new(files.state_path).write(state)
      FileUtils.rm_f(files.paused_reason_path)

      puts 'Updated autowork review base.'
      puts "- task: #{task_folder}"
      puts "- review_base_ref: #{new_base_ref}"
      puts "- review_base_commit: #{new_base_commit}"
      unless repo.ancestor?(new_base_ref, 'HEAD')
        puts '- warning: new base is not an ancestor of HEAD; rebase/branch-base cleanup may still be needed before PR review.'
      end
    end
  end

  class Initializer
    def initialize(argv)
      @argv = argv
    end

    def run
      setup = RunSetup.new(@argv).prepare!
      puts 'Initialized autowork run'
      puts "task_folder=#{setup.context.task_folder}"
      puts "repo=#{setup.repo.root}"
      puts "steps_count=#{setup.steps.count}"
      puts "pi_manager_target=#{setup.roles.manager.id}"
      puts "pi_worker_target=#{setup.roles.pi_worker.id}"
      puts "claude_worker_target=#{setup.roles.claude_worker.id}"
      puts "first_prompt=#{setup.files.prompt_path("step#{setup.steps.numbers.first}_pi_implement_request.md")}"
      puts
      puts 'Next manual/integration step: run autowork normally to send the prompt.'
    end
  end

  class CLI
    def initialize(argv)
      @argv = argv
    end

    def run
      command = @argv.first
      case command
      when 'help', '-h', '--help'
        puts usage
      when 'doctor'
        Doctor.new(@argv[1..]).run
      when 'init'
        Initializer.new(@argv[1..]).run
      when 'status'
        show_status(@argv[1..])
      when 'manager-review-fix'
        ManagerReviewFix.new(@argv[1..]).run
      when 'manager-review-pass'
        ManagerReviewPass.new(@argv[1..]).run
      when 'rebase-base'
        BaseRebaser.new(@argv[1..]).run
      when 'update-base'
        BaseRefUpdater.new(@argv[1..]).run
      else
        Orchestrator.new(@argv).run
      end
    rescue Error => e
      warn "autowork: #{e.message}"
      exit 1
    end

    private

    def usage
      <<~USAGE
        Usage:
          autowork [task_id] [full-base-branch-or-ref]
          autowork [project-or-session] [task_id] [full-base-branch-or-ref]
          autowork init [task_id] [full-base-branch-or-ref]
          autowork init [project-or-session] [task_id] [full-base-branch-or-ref]
          autowork doctor [--no-send-test]
          autowork status <task_folder>
          autowork rebase-base [base-ref]
          autowork update-base <task_folder> <new-base-ref>
          autowork manager-review-fix <task_folder>
          autowork manager-review-pass <task_folder>
      USAGE
    end

    def show_status(args)
      task_folder = args&.first
      raise Error, 'Usage: autowork status <task_folder>' unless task_folder

      state_path = File.join(task_folder, 'autowork-log', 'state.json')
      config_path = File.join(task_folder, 'autowork-log', 'config.yml')
      puts File.read(config_path) if File.file?(config_path)
      puts JSON.pretty_generate(StateStore.new(state_path).read)
    end
  end
end
