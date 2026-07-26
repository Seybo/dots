# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'json'
require 'time'
require 'yaml'

require_relative '../../autowork/lib/autowork'

module Addressit
  class Error < StandardError; end

  TASK_ROOT = '/Volumes/dev/_tasks'
  DOTS_REPO = '/Users/inseybo/.dots'
  DEFAULT_MAX_FIX_ITERATIONS = 5
  DEFAULT_MAX_TOTAL_COMMITS = 10

  Context = Struct.new(:project, :task_id, :task_folder, :repo_root, :branch, :pr_repo, :pr_number, keyword_init: true)

  class TaskResolver
    def initialize(cwd: Dir.pwd, shell: Autowork::Shell, projects_file: Autowork::PROJECTS_FILE)
      @cwd = File.expand_path(cwd)
      @shell = shell
      @registry = Autowork::ProjectRegistry.new(projects_file)
    end

    def resolve(task_id: nil)
      repo_root = File.realpath(@shell.capture!('git', '-C', @cwd, 'rev-parse', '--show-toplevel').strip)
      project = infer_project(repo_root)
      task_root = File.join(TASK_ROOT, project)
      raise Error, "Task project not found: #{task_root}" unless File.directory?(task_root)

      branch = @shell.capture!('git', '-C', repo_root, 'branch', '--show-current').strip
      task_id ||= infer_task_id(branch)
      raise Error, "No task folder found for branch #{branch.inspect}. Pass --task <local-task-id>." unless task_id

      matches = Dir.glob(File.join(task_root, "#{task_id}*")).select { |path| File.directory?(path) }
      raise Error, "No task folder found for #{project}/#{task_id}." if matches.empty?
      raise Error, "Multiple task folders found for #{project}/#{task_id}:\n#{matches.join("\n")}" if matches.length > 1

      task_folder = matches.first
      unless File.file?(File.join(task_folder, 'task.md'))
        raise Error, "No task folder found for #{project}/#{task_id}: missing task.md."
      end

      Context.new(project: project, task_id: task_id, task_folder: task_folder, repo_root: repo_root, branch: branch)
    end

    private

    def infer_project(path)
      return 'env' if path == DOTS_REPO || path.start_with?("#{DOTS_REPO}/")

      project_and_workspace = @registry.project_and_workspace_for_path(path)
      return project_and_workspace.first if project_and_workspace

      raise Error, "Could not infer project from #{path.inspect}. Pass a checkout in a known project."
    end

    def infer_task_id(branch)
      match = branch.match(%r{(?:^|/)sc-(\d+)(?:/|$)})
      return match[1] if match

      nil
    end
  end

  class Files
    attr_reader :task_folder, :log_dir

    def initialize(task_folder)
      @task_folder = task_folder
      @log_dir = File.join(task_folder, 'addressit-log')
    end

    def mkdirs
      %w[prompts reviews audits debates status rounds].each { |name| FileUtils.mkdir_p(File.join(log_dir, name)) }
    end

    def config_path = File.join(log_dir, 'config.yml')
    def state_path = File.join(log_dir, 'state.json')
    def lock_path = File.join(log_dir, 'run.lock')
    def final_checks_path = File.join(log_dir, 'final_checks.md')
    def manager_review_path = File.join(log_dir, 'manager_review.md')
    def manager_findings_path = File.join(log_dir, 'manager_review_findings.json')
    def prompt_path(name) = File.join(log_dir, 'prompts', name)
    def round_path(round, name) = File.join(log_dir, 'rounds', "round#{round}_#{name}")
    def comments_path(round) = round_path(round, 'comments.json')
    def triage_path(round) = round_path(round, 'triage.json')
    def approval_path(round) = round_path(round, 'approval.json')
    def review_path(round, iteration) = File.join(log_dir, 'reviews', "round#{round}_claude_review#{iteration}.md")
    def audit_path(round, agent) = File.join(log_dir, 'audits', "round#{round}_#{agent}_blind_audit.md")
    def manager_hypotheses_path(round) = File.join(log_dir, 'audits', "round#{round}_manager_initial_review_hypotheses.json")
    def risk_manifest_path(round) = File.join(log_dir, 'audits', "round#{round}_risk_coverage_manifest.json")
    def reconciliation_path(round) = File.join(log_dir, 'audits', "round#{round}_risk_reconciliation.json")
    def status_path(round, agent, phase, iteration = nil)
      suffix = iteration ? "#{phase}#{iteration}" : phase
      File.join(log_dir, 'status', "round#{round}_#{agent}_#{suffix}.json")
    end
  end

  class Store
    def initialize(path)
      @path = path
    end

    def read
      raise Error, "Missing addressit state: #{@path}" unless File.file?(@path)

      data = JSON.parse(File.read(@path))
      raise Error, 'Addressit state must be a JSON object' unless data.is_a?(Hash)

      data
    rescue JSON::ParserError => e
      raise Error, "Invalid addressit state: #{e.message}"
    end

    def write(data)
      FileUtils.mkdir_p(File.dirname(@path))
      data['updated_at'] = Time.now.iso8601
      File.write(@path, JSON.pretty_generate(data) + "\n")
    end
  end

  class Lock
    def initialize(path)
      @path = path
    end

    def acquire!
      FileUtils.mkdir_p(File.dirname(@path))
      File.open(@path, File::WRONLY | File::CREAT | File::EXCL) { |file| file.write("#{Process.pid}\n") }
    rescue Errno::EEXIST
      raise Error, "Addressit is already running: #{@path}"
    end

    def release
      FileUtils.rm_f(@path)
    end
  end

  class ClipboardReview
    def initialize(shell: Autowork::Shell)
      @shell = shell
    end

    def comments
      text = @shell.capture!('pbpaste')
      raise Error, 'Clipboard review is empty' if text.strip.empty?

      id = "local-#{Digest::SHA256.hexdigest(text)[0, 16]}"
      now = Time.now.iso8601
      [{
        'id' => id,
        'kind' => 'local_review',
        'path' => nil,
        'line' => nil,
        'body' => text,
        'created_at' => now,
        'updated_at' => now,
        'user' => { 'login' => 'local-review' },
        'html_url' => nil
      }]
    end
  end

  class GitHub
    attr_reader :repo, :number

    def initialize(argv, shell: Autowork::Shell)
      @argv = argv.dup
      @shell = shell
      @repo, @number, @specific_comment, @specific_review = parse_target
      @filters = parse_filters
      raise Error, "Invalid comment filter: #{@argv.join(' ').inspect}" unless @filters
    end

    def comments
      inline = fetch("repos/#{repo}/pulls/#{number}/comments").map { |comment| normalize(comment, 'inline_review_comment') }
      comments = inline
      if include_all_comments? || inline.empty?
        summaries = fetch("repos/#{repo}/pulls/#{number}/reviews").map { |comment| normalize(comment, 'review_summary') }
        issue_comments = fetch("repos/#{repo}/issues/#{number}/comments").map { |comment| normalize(comment, 'issue_comment') }
        comments += summaries + issue_comments
      end

      comments = comments.select { |comment| comment['id'].to_s == @specific_comment.to_s } if @specific_comment
      if @specific_review
        comments = comments.select do |comment|
          comment['pull_request_review_id'].to_s == @specific_review.to_s ||
            (comment['kind'] == 'review_summary' && comment['id'].to_s == @specific_review.to_s)
        end
      end
      comments = apply_filters(comments)
      comments.uniq { |comment| [comment['id'], comment['kind']] }.sort_by { |comment| comment['created_at'].to_s }
    rescue JSON::ParserError => e
      raise Error, "Could not parse GitHub review comments: #{e.message}"
    end

    def fetch(path)
      response = JSON.parse(@shell.capture!('gh', 'api', path, '--paginate'))
      raise Error, "GitHub returned a non-array response for #{path}" unless response.is_a?(Array)

      response
    end

    def normalize(comment, kind)
      comment.merge(
        'kind' => kind,
        'created_at' => comment['created_at'] || comment['submitted_at'],
        'updated_at' => comment['updated_at'] || comment['submitted_at'] || comment['created_at']
      )
    end

    def include_all_comments?
      filters&.fetch(:all_comments, false)
    end

    private

    def parse_target
      target = @argv.shift
      unless target&.match?(/\A\d+\z/) || target&.match?(%r{\Ahttps?://github\.com/[^/]+/[^/]+/pull/\d+})
        @argv.unshift(target) if target
        raise Error, "Invalid PR target: #{target.inspect}" if target && !implicit_filter?

        target = current_pull_request
      end

      if target&.match?(%r{\Ahttps?://github\.com/[^/]+/[^/]+/pull/\d+})
        match = target.match(%r{github\.com/([^/]+)/([^/]+)/pull/(\d+)(?:#(.*))?})
        fragment = match[4].to_s
        specific_comment = fragment[/discussion_r(\d+)/, 1]
        specific_review = fragment[/pullrequestreview-(\d+)/, 1]
        return ["#{match[1]}/#{match[2]}", match[3], specific_comment, specific_review]
      end

      raise Error, "Invalid PR target: #{target.inspect}" unless target&.match?(/\A\d+\z/)

      repository = @shell.capture!('gh', 'repo', 'view', '--json', 'nameWithOwner', '-q', '.nameWithOwner').strip
      [repository, target, nil, nil]
    end

    def implicit_filter?
      !filters.nil?
    end

    def filters
      @filters ||= parse_filters
    end

    def parse_filters
      text = @argv.join(' ').strip
      return {} if text.empty?

      prefix = text.match?(/\Aall\s+comments\b/i) ? 'all comments' : nil
      text = text.sub(/\Aall\s+comments\s*/i, '') if prefix
      conversational_comments = !prefix && text.match?(/\Acomments\z/i)
      text = text.sub(/\Acomments(?:\s+|\z)/i, '') unless prefix
      reviewer = nil
      since = nil
      if (match = text.match(/\Afrom\s+@?([A-Za-z0-9_-]+)(?:\s+since\s+(.+))?\z/i))
        reviewer = match[1]
        since = match[2]
      elsif (match = text.match(/\Asince\s+(.+)\z/i))
        since = match[1]
      elsif !text.empty?
        return nil
      end
      return nil if !prefix && !conversational_comments && !reviewer && !since
      parse_time(since) if since

      { all_comments: !prefix.nil?, reviewer: reviewer, since: since }
    end

    def current_pull_request
      payload = JSON.parse(@shell.capture!('gh', 'pr', 'view', '--json', 'number,url'))
      unless payload.is_a?(Hash) && payload['number'].to_s.match?(/\A\d+\z/) && payload['url'].is_a?(String) && payload['url'].match?(%r{\Ahttps?://github\.com/[^/]+/[^/]+/pull/\d+})
        raise Error, 'Could not find a valid pull request for the current branch'
      end

      payload['url']
    rescue JSON::ParserError => e
      raise Error, "Could not parse current pull request: #{e.message}"
    end

    def apply_filters(comments)
      filters = self.filters
      raise Error, "Invalid comment filter: #{@argv.join(' ').inspect}" unless filters

      if filters[:reviewer]
        comments = comments.select { |comment| comment.dig('user', 'login') == filters[:reviewer] }
      end
      return comments unless filters[:since]

      threshold = parse_time(filters[:since])
      comments.select do |comment|
        [comment['created_at'], comment['updated_at']].compact.any? { |value| Time.parse(value) >= threshold }
      end
    end

    def parse_time(value)
      begin
        return Time.parse(value) if value.match?(/\d{4}-\d{2}-\d{2}T/)

        seconds = case value.strip.downcase
                  when /^(\d+)\s+hours?\s+ago$/ then Regexp.last_match(1).to_i * 3600
                  when /^yesterday$/ then 86_400
                  else raise Error, "Could not parse since filter #{value.inspect}"
                  end
        Time.now - seconds
      rescue ArgumentError => e
        raise Error, "Could not parse since filter #{value.inspect}: #{e.message}"
      end
    end
  end

  class Ledger
    def initialize(state)
      @state = state
    end

    def addressed_or_skipped?(comment)
      entry = find(comment)
      entry && entry['updated_at'] == comment['updated_at'] && %w[addressed skipped].include?(entry['state'])
    end

    def find(comment)
      kind = comment.fetch('kind', 'inline_review_comment')
      Array(@state['comment_ledger']).reverse.find do |entry|
        entry['kind'].to_s == kind && entry['id'].to_s == comment['id'].to_s
      end
    end

    def save(comment, state:, **attributes)
      entry = find(comment)
      if entry
        entry.merge!('state' => state, 'updated_at' => comment['updated_at'], **attributes)
      else
        @state['comment_ledger'] ||= []
        @state['comment_ledger'] << {
          'id' => comment['id'].to_s,
          'kind' => comment.fetch('kind', 'inline_review_comment'),
          'updated_at' => comment['updated_at'],
          'state' => state,
          **attributes
        }
      end
    end
  end

  class PromptWriter
    def initialize(files, context, state)
      @files = files
      @context = context
      @state = state
    end

    def pi_implement
      round = @state.fetch('current_round')
      path = @files.prompt_path("round#{round}_pi_implement_request.md")
      status = @files.status_path(round, 'pi', 'implement')
      FileUtils.rm_f(status)
      File.write(path, <<~PROMPT)
        # Addressit: implement approved PR review comments for round #{round}

        You are the Pi implementation agent participating in `/addressit` as `pi-worker`.
        Work only in #{@context.repo_root}.

        Read:
        - task: #{@context.task_folder}/task.md
        - comments: #{@files.comments_path(round)}
        - approval: #{@files.approval_path(round)}
        - addressit state: #{@files.state_path}

        Implement every comment whose decision is `approved` in the approval file. Address them together as one coherent change. Do not fix skipped comments or unrelated issues.

        Rules:
        - Do not commit or stage changes. Leave repo changes for `/addressit` to commit.
        - Inspect the current code path before deciding how to fix a comment.
        - Run focused checks when useful and report them.
        - If an approved comment is invalid or impossible after inspecting the code, stop and explain it in the status summary instead of silently changing scope.
        - Write valid status JSON last to: #{status}
        - After writing status JSON, stop immediately.

        Required status shape:
        {"status":"done","agent":"pi","phase":"implement","step":0,"summary":"...","checks_run":[]}
        PROMPT
      path
    end

    def pi_blind_audit
      round = @state.fetch('current_round')
      path = @files.prompt_path("round#{round}_pi_blind_audit_request.md")
      status = @files.status_path(round, 'pi', 'audit')
      audit = @files.audit_path(round, 'pi')
      FileUtils.rm_f(status)
      FileUtils.rm_f(audit)
      File.write(path, <<~PROMPT)
        # Addressit: blind whole-diff audit for round #{round}

        You are the Pi review agent participating in `/addressit` as `pi-worker`.
        Review the complete current diff in #{@context.repo_root} after the implementation commit.

        Read:
        - task: #{@context.task_folder}/task.md
        - addressit state: #{@files.state_path}

        This is an independent discovery pass. Do not read manager hypotheses, historical risk files, or other audit artifacts. Do not edit files and do not run tests, linters, or formatters.

        Look for correctness, concurrency, idempotency, external-boundary, partial-failure, data-integrity, time/identity, and operator-behavior risks that the implementation introduced. Do not limit the review to the approved comments.

        Write the concise human-readable audit to #{audit}. Write valid status JSON last to #{status}, then stop immediately.
        Required status shape:
        {"status":"done","agent":"pi","phase":"audit","step":0,"summary":"...","findings":[{"id":"P1","severity":"BLOCKER|MINOR","title":"...","body":"..."}]}
        Use an empty findings array when no actionable findings remain. Use status `needs_user` with a question if input is required.
      PROMPT
      path
    end

    def claude_review(iteration, commit_sha)
      round = @state.fetch('current_round')
      path = @files.prompt_path("round#{round}_claude_review#{iteration}_request.md")
      status = @files.status_path(round, 'claude', 'review', iteration)
      review = @files.review_path(round, iteration)
      FileUtils.rm_f(status)
      FileUtils.rm_f(review)
      File.write(path, <<~PROMPT)
        # Addressit: review round #{round}, iteration #{iteration}

        You are the Claude review agent participating in `/addressit` as `claude-worker`.
        Review commit #{commit_sha} in #{@context.repo_root}.

        Read:
        - task: #{@context.task_folder}/task.md
        - comments: #{@files.comments_path(round)}
        - approval: #{@files.approval_path(round)}
        - addressit state: #{@files.state_path}

        Review every approved comment and the complete current diff, not only the comment locations. Independently look for correctness, concurrency, idempotency, external-boundary, partial-failure, data-integrity, time/identity, and operator-behavior risks. Do not read manager hypotheses, historical risk files, or Pi's blind audit. Do not edit files and do not run tests, linters, or formatters. Use read-only inspection and Pi's reported checks.
        Write the full human-readable review to #{review} before the status JSON.
        Write valid status JSON last to #{status}, then stop immediately.

        Required status shape:
        {"status":"done","agent":"claude","phase":"review","step":0,"summary":"...","findings":[{"id":"F1","severity":"BLOCKER|MINOR","title":"...","body":"..."}]}
        Use an empty findings array when the commit is accepted. Use status `needs_user` with a question if user input is required.
        PROMPT
      path
    end

    def pi_classify(iteration, findings)
      round = @state.fetch('current_round')
      path = @files.prompt_path("round#{round}_pi_classify#{iteration}_request.md")
      status = @files.status_path(round, 'pi', 'classify', iteration)
      FileUtils.rm_f(status)
      File.write(path, <<~PROMPT)
        # Addressit: classify Claude findings for round #{round}

        You are the Pi implementation agent participating in `/addressit` as `pi-worker`.
        Do not edit repo files in this turn.

        Classify every finding in this JSON:
        #{JSON.pretty_generate(findings)}

        Allowed decisions:
        - accept: fix the finding
        - accept_with_alternative_fix: fix it with a safer local alternative
        - dispute: explain why it is invalid or unreachable
        - follow_up: valid non-minor issue outside this PR comment batch
        - needs_user: user decision is required

        Write a rationale file beside the status JSON if useful. Write valid status JSON last to #{status}, then stop immediately.
        Required shape:
        {"status":"done","agent":"pi","phase":"classify","step":0,"summary":"...","resolutions":[{"finding_id":"F1","decision":"accept","rationale":"..."}]}
        PROMPT
      path
    end

    def claude_debate(iteration, findings, resolutions)
      round = @state.fetch('current_round')
      path = @files.prompt_path("round#{round}_claude_debate#{iteration}_request.md")
      status = @files.status_path(round, 'claude', 'debate', iteration)
      FileUtils.rm_f(status)
      File.write(path, <<~PROMPT)
        # Addressit: debate disputed findings for round #{round}

        You are the Claude review agent participating in `/addressit` as `claude-worker`.
        Do not edit files or run checks. Reconsider these disputed findings using Pi's rationale:

        Findings:
        #{JSON.pretty_generate(findings)}

        Pi resolutions:
        #{JSON.pretty_generate(resolutions)}

        For every finding, choose one decision: `accept`, `agree_with_pi`, `still_disagree`, or `needs_user`.
        Write valid status JSON last to #{status}, then stop immediately.
        Required shape:
        {"status":"done","agent":"claude","phase":"debate","step":0,"summary":"...","debates":[{"finding_id":"F1","decision":"accept","rationale":"..."}]}
        PROMPT
      path
    end

    def pi_debate(iteration, findings, resolutions, claude_debates)
      round = @state.fetch('current_round')
      path = @files.prompt_path("round#{round}_pi_debate#{iteration}_request.md")
      status = @files.status_path(round, 'pi', 'debate', iteration)
      FileUtils.rm_f(status)
      File.write(path, <<~PROMPT)
        # Addressit: resolve disputed findings for round #{round}

        You are the Pi implementation agent participating in `/addressit` as `pi-worker`.
        Do not edit files in this turn.

        Reconsider each disputed finding after Claude's response.
        Findings:
        #{JSON.pretty_generate(findings)}

        Original Pi resolutions:
        #{JSON.pretty_generate(resolutions)}

        Claude debate response:
        #{JSON.pretty_generate(claude_debates)}

        For every finding, choose one decision: `accept`, `agree_with_pi`, `still_disagree`, or `needs_user`.
        Write valid status JSON last to #{status}, then stop immediately.
        Required shape:
        {"status":"done","agent":"pi","phase":"debate","step":0,"summary":"...","debates":[{"finding_id":"F1","decision":"accept","rationale":"..."}]}
        PROMPT
      path
    end

    def pi_manager_fix(iteration, findings)
      round = @state.fetch('current_round')
      path = @files.prompt_path("round#{round}_pi_manager_fix#{iteration}_request.md")
      status = @files.status_path(round, 'pi', 'manager_fix', iteration)
      FileUtils.rm_f(status)
      File.write(path, <<~PROMPT)
        # Addressit: fix pi-manager findings for round #{round}

        You are the Pi implementation agent participating in `/addressit` as `pi-worker`.
        Work only in #{@context.repo_root}. Do not commit or stage changes.

        Fix every manager finding below. These are manager-context requirements; do not dispute or silently defer them.
        #{JSON.pretty_generate(findings)}

        Run focused checks if useful. Leave changes unstaged for `/addressit` to commit. Write valid status JSON last to #{status}, then stop immediately.
        Required shape:
        {"status":"done","agent":"pi","phase":"manager_fix","step":0,"summary":"...","checks_run":[]}
        PROMPT
      path
    end

    def pi_fix(iteration, findings, resolutions)
      round = @state.fetch('current_round')
      path = @files.prompt_path("round#{round}_pi_fix#{iteration}_request.md")
      status = @files.status_path(round, 'pi', 'fix', iteration)
      FileUtils.rm_f(status)
      File.write(path, <<~PROMPT)
        # Addressit: fix review findings for round #{round}

        You are the Pi implementation agent participating in `/addressit` as `pi-worker`.
        Work only in #{@context.repo_root}. Do not commit or stage changes.

        Fix only these accepted Claude findings:
        #{JSON.pretty_generate(findings.filter_map do |finding|
          resolution = resolutions.find { |item| item['finding_id'] == finding['id'] }
          resolution && %w[accept accept_with_alternative_fix].include?(resolution['decision']) ? [finding, resolution] : nil
        end)}

        Run focused checks if useful. Leave changes unstaged for `/addressit` to commit. Write valid status JSON last to #{status}, then stop immediately.
        Required shape:
        {"status":"done","agent":"pi","phase":"fix","step":0,"summary":"...","checks_run":[]}
        PROMPT
      path
    end
  end

  class Orchestrator
    WAITING_STAGE_NAMES = {
      'waiting_for_pi' => 'PI WORKER IMPLEMENTATION',
      'waiting_for_pi_audit' => 'PI BLIND AUDIT',
      'waiting_for_manager_fix' => 'PI MANAGER FIX',
      'waiting_for_claude' => 'CLAUDE REVIEW',
      'waiting_for_fix_review' => 'CLAUDE FIX REVIEW',
      'waiting_for_classify' => 'PI FINDING CLASSIFICATION',
      'waiting_for_claude_debate' => 'CLAUDE DEBATE',
      'waiting_for_pi_debate' => 'PI DEBATE',
      'waiting_for_fix' => 'PI FIX'
    }.freeze

    def initialize(context, files, state, tmux: Autowork::Tmux.new, shell: Autowork::Shell)
      @context = context
      @files = files
      @state = state
      @tmux = tmux
      @shell = shell
      @repo = Autowork::GitRepo.new(context.repo_root)
    end

    def prepare_round!(source)
      raise Error, "Refusing to start with dirty worktree in #{@context.repo_root}:\n#{@repo.status}" unless @repo.clean?

      comments = source.comments
      candidates = comments.reject { |comment| Ledger.new(@state).addressed_or_skipped?(comment) }
      @state['github_comments_fetched_at'] = Time.now.iso8601
      @state['current_round'] = (@state['rounds'].map { |round| round['number'] }.max || 0) + 1
      round = @state['current_round']
      File.write(@files.comments_path(round), JSON.pretty_generate(candidates) + "\n")
      @state['rounds'] << {
        'number' => round,
        'selected_ids' => candidates.map { |comment| comment['id'].to_s },
        'baseline_head' => @repo.head_sha,
        'round_start_head' => @repo.head_sha,
        'commit_shas' => [],
        'status' => 'awaiting_approval'
      }
      @state['phase'] = candidates.empty? ? 'no_new_comments' : 'awaiting_round_approval'
      save_state
      print_selection(candidates, round)
    end

    def approve!(approval_path)
      round = @state.fetch('current_round')
      raise Error, "Addressit is not waiting for approval (phase #{@state['phase']})" unless @state['phase'] == 'awaiting_round_approval'
      approval = JSON.parse(File.read(approval_path))
      comments = JSON.parse(File.read(@files.comments_path(round)))
      decisions = Array(approval['comments']).to_h { |item| [item['id'].to_s, item] }
      selected_ids = comments.map { |comment| comment['id'].to_s }
      unless decisions.keys.sort == selected_ids.sort
        raise Error, "Approval must classify every selected comment exactly once"
      end

      ledger = Ledger.new(@state)
      approved = []
      skipped = []
      comments.each do |comment|
        item = decisions.fetch(comment['id'].to_s)
        decision = item['decision'].to_s
        raise Error, "Invalid decision for comment #{comment['id']}: #{decision.inspect}" unless %w[approved skipped].include?(decision)

        ledger.save(comment, state: decision, minor: !!item['minor'], valid: !!item['valid'], rationale: item['rationale'].to_s)
        decision == 'approved' ? approved << comment['id'].to_s : skipped << comment['id'].to_s
      end
      destination = @files.approval_path(round)
      FileUtils.cp(approval_path, destination) unless File.expand_path(approval_path) == File.expand_path(destination)
      round_state = @state['rounds'].find { |entry| entry['number'] == round }
      round_state.merge!('approved_ids' => approved, 'skipped_ids' => skipped, 'status' => approved.empty? ? 'skipped' : 'approved', 'risk_audit_required' => !approved.empty?)
      @state['phase'] = approved.empty? ? 'round_skipped' : 'ready_to_send_pi'
      save_state
      puts "Approved #{approved.length} comment(s); skipped #{skipped.length}."
      run unless approved.empty?
    rescue JSON::ParserError => e
      raise Error, "Invalid approval JSON: #{e.message}"
    end

    def run
      loop do
        case @state['phase']
        when 'ready_to_send_pi'
          send_pi
        when 'waiting_for_pi'
          wait_for('pi', 'implement') { @state['phase'] = 'ready_to_commit' }
        when 'ready_for_manager_hypotheses'
          print_manager_hypotheses_gate
          return
        when 'ready_to_send_pi_audit'
          send_pi_audit
        when 'waiting_for_pi_audit'
          wait_for('pi', 'audit') { handle_pi_audit }
        when 'ready_for_risk_reconciliation'
          print_risk_reconciliation_gate
          return
        when 'waiting_for_manager_fix'
          wait_for('pi', 'manager_fix', @state.fetch('manager_fix_iteration')) { commit_manager_fix }
        when 'ready_to_commit'
          commit_implementation
        when 'waiting_for_claude'
          wait_for('claude', 'review', @state.fetch('review_iteration')) { handle_claude_review }
        when 'ready_to_send_classify'
          send_classify
        when 'waiting_for_classify'
          wait_for('pi', 'classify', @state.fetch('review_iteration')) { handle_classification }
        when 'ready_to_send_claude_debate'
          send_claude_debate
        when 'waiting_for_claude_debate'
          wait_for('claude', 'debate', @state.fetch('debate_round')) { handle_claude_debate }
        when 'ready_to_send_pi_debate'
          send_pi_debate
        when 'waiting_for_pi_debate'
          wait_for('pi', 'debate', @state.fetch('debate_round')) { handle_pi_debate }
        when 'ready_to_send_fix'
          send_fix
        when 'waiting_for_fix'
          wait_for('pi', 'fix', @state.fetch('fix_iteration')) { commit_fix }
        when 'waiting_for_fix_review'
          wait_for('claude', 'review', @state.fetch('review_iteration')) { handle_claude_review }
        when 'ready_for_final_checks'
          run_final_checks
        when 'ready_for_manager_review'
          print_manager_gate
          return
        when 'awaiting_round_approval', 'no_new_comments', 'round_skipped', 'complete', 'awaiting_user'
          return
        else
          raise Error, "Unknown addressit phase: #{@state['phase'].inspect}"
        end
      end
    end

    def start_audit!(hypotheses_path)
      raise Error, "Addressit is not waiting for manager hypotheses (phase #{@state['phase']})" unless @state['phase'] == 'ready_for_manager_hypotheses'

      hypotheses = JSON.parse(File.read(hypotheses_path))
      validate_hypotheses!(hypotheses)
      destination = @files.manager_hypotheses_path(@state.fetch('current_round'))
      FileUtils.cp(hypotheses_path, destination) unless File.expand_path(hypotheses_path) == File.expand_path(destination)
      @state['phase'] = 'ready_to_send_pi_audit'
      @state['manager_hypotheses_path'] = destination
      save_state
      run
    rescue JSON::ParserError => e
      raise Error, "Invalid manager hypotheses JSON: #{e.message}"
    end

    def reconcile_audit!(manifest_path)
      raise Error, "Addressit is not waiting for risk reconciliation (phase #{@state['phase']})" unless @state['phase'] == 'ready_for_risk_reconciliation'

      manifest = Autowork::ReviewRiskManifest.validate_file(manifest_path)
      validate_hypothesis_coverage!(manifest)
      gaps = manifest['coverage_gaps']
      raise Error, 'Risk reconciliation has unresolved coverage gaps' unless gaps.empty?
      destination = @files.risk_manifest_path(@state.fetch('current_round'))
      FileUtils.cp(manifest_path, destination) unless File.expand_path(manifest_path) == File.expand_path(destination)
      pi_findings = @state.fetch('review_iteration', 1) == 1 ? @state.fetch('pi_audit_findings', []) : []
      findings = tagged_findings(pi_findings, 'PI') + tagged_findings(@state.fetch('claude_findings', []), 'CL') + Array(manifest['additional_findings'])
      @state['audit_findings'] = findings.uniq { |finding| finding['id'] }
      @state['risk_manifest_path'] = destination
      @state['risk_reconciliation_path'] = @files.reconciliation_path(@state.fetch('current_round'))
      File.write(@state['risk_reconciliation_path'], JSON.pretty_generate('summary' => manifest['summary'], 'coverage_gaps' => gaps, 'findings_count' => findings.length) + "\n")
      @state['claude_findings'] = @state['audit_findings']
      @state['phase'] = findings.empty? ? 'ready_for_final_checks' : 'ready_to_send_classify'
      save_state
      run
    rescue JSON::ParserError => e
      raise Error, "Invalid risk manifest JSON: #{e.message}"
    end

    def manager_fix!(findings_path)
      raise Error, "Addressit is not waiting for manager review (phase #{@state['phase']})" unless @state['phase'] == 'ready_for_manager_review'

      findings = JSON.parse(File.read(findings_path))
      findings = findings['findings'] if findings.is_a?(Hash)
      raise Error, 'Manager findings must be a non-empty array' unless findings.is_a?(Array) && !findings.empty?

      round = @state.fetch('current_round')
      iteration = (@state['manager_fix_iteration'] || 0) + 1
      @state['manager_fix_iteration'] = iteration
      @state['manager_findings'] = findings
      round_state = @state['rounds'].find { |entry| entry['number'] == round }
      round_state['baseline_head'] = @repo.head_sha
      path = PromptWriter.new(@files, @context, @state).pi_manager_fix(iteration, findings)
      send_prompt(path)
      @state['phase'] = 'waiting_for_manager_fix'
      save_state
      run
    rescue JSON::ParserError => e
      raise Error, "Invalid manager findings JSON: #{e.message}"
    end

    def resolve_user!(resolution_path)
      raise Error, "Addressit is not waiting for user input (phase #{@state['phase']})" unless @state['phase'] == 'awaiting_user'

      data = JSON.parse(File.read(resolution_path))
      resolutions = Array(data['findings'])
      finding_ids = Array(@state['claude_findings']).map { |finding| finding['id'] }
      decisions = resolutions.to_h { |resolution| [resolution['finding_id'].to_s, resolution] }
      raise Error, 'User resolution must classify every Claude finding' unless decisions.keys.sort == finding_ids.sort

      invalid = resolutions.reject { |resolution| %w[accept skip].include?(resolution['decision']) }
      raise Error, "Invalid user resolution decision(s): #{invalid.map { |item| item['decision'] }.uniq.join(', ')}" unless invalid.empty?

      accepted = resolutions.select { |resolution| resolution['decision'] == 'accept' }
      @state['accepted_resolutions'] = accepted.map do |resolution|
        { 'finding_id' => resolution['finding_id'], 'decision' => 'accept', 'rationale' => resolution['rationale'].to_s }
      end
      @state.delete('question')
      if accepted.empty?
        @state['phase'] = 'ready_for_final_checks'
      else
        @state['fix_iteration'] = (@state['fix_iteration'] || 0) + 1
        @state['phase'] = 'ready_to_send_fix'
      end
      save_state
      run
    rescue JSON::ParserError => e
      raise Error, "Invalid user resolution JSON: #{e.message}"
    end

    def manager_pass!
      raise Error, "Addressit is not waiting for manager review (phase #{@state['phase']})" unless @state['phase'] == 'ready_for_manager_review'
      raise Error, "Write #{@files.manager_review_path} before passing manager review" unless File.file?(@files.manager_review_path)
      round = @state.fetch('current_round')
      comments = JSON.parse(File.read(@files.comments_path(round)))
      round_state = @state['rounds'].find { |entry| entry['number'] == round }
      manifest = nil
      if round_state['risk_audit_required']
        raise Error, "Complete risk reconciliation before passing manager review: #{@files.risk_manifest_path(round)}" unless File.file?(@files.risk_manifest_path(round)) && File.file?(@files.reconciliation_path(round))
        manifest = Autowork::ReviewRiskManifest.validate_file(@files.risk_manifest_path(round))
        raise Error, 'Risk reconciliation has unresolved coverage gaps' unless Array(manifest['coverage_gaps']).empty?
      end
      squash_round_commits!(round_state)
      Autowork::ReviewRiskRegistry.new(@context.project).apply!(
        Array(manifest && manifest['registry_updates']),
        task_id: @context.task_id,
        round_id: "addressit-#{round}",
      ) if manifest
      approved_ids = round_state.fetch('approved_ids')
      ledger = Ledger.new(@state)
      comments.select { |comment| approved_ids.include?(comment['id'].to_s) }.each do |comment|
        ledger.save(comment, state: 'addressed')
      end
      round_state['status'] = 'addressed'
      @state['phase'] = 'complete'
      save_state
      puts "Addressit round #{round} complete. Marked #{approved_ids.length} comment(s) addressed."
    end

    private

    def send_pi
      path = PromptWriter.new(@files, @context, @state).pi_implement
      send_prompt(path)
      @state['phase'] = 'waiting_for_pi'
      save_state
    end

    def record_commit(commit_sha)
      @state['commits'] << commit_sha
      round_state = @state['rounds'].find { |entry| entry['number'] == @state.fetch('current_round') }
      round_state['commit_shas'] ||= []
      round_state['commit_shas'] << commit_sha
    end

    def squash_round_commits!(round_state)
      commit_shas = Array(round_state['commit_shas'])
      raise Error, 'Cannot finalize review round without recorded commits' if commit_shas.empty?

      base_sha = round_state.fetch('round_start_head')
      message = "Add review updates #{round_state.fetch('number')}"
      squashed_sha = @repo.squash_commits(base_sha, message)
      @state['commits'] = @state.fetch('commits').reject { |sha| commit_shas.include?(sha) }
      @state['commits'] << squashed_sha
      round_state['commit_shas'] = [squashed_sha]
      round_state['squashed_from'] = commit_shas
      round_state['squashed_commit'] = squashed_sha
    end

    def commit_implementation
      ensure_clean_before_commit!
      raise Error, 'Pi-worker reported completion but produced no repository changes' if @repo.clean?

      @repo.add_all
      commit_sha = @repo.commit("Address PR #{@context.pr_number} round #{@state.fetch('current_round')}")
      record_commit(commit_sha)
      @state['review_iteration'] = 1
      @state['phase'] = 'ready_for_manager_hypotheses'
      save_state
      print_manager_hypotheses_gate
    end

    def send_pi_audit
      @state['next_agent'] = 'pi'
      path = PromptWriter.new(@files, @context, @state).pi_blind_audit
      send_prompt(path)
      @state['phase'] = 'waiting_for_pi_audit'
      save_state
    end

    def handle_pi_audit
      status = read_status('pi', 'audit')
      require_nonempty_artifact!(@files.audit_path(@state.fetch('current_round'), 'pi'), 'Pi blind audit')
      @state['pi_audit_findings'] = actionable_findings(status['findings'])
      @state['phase'] = 'ready_to_send_claude'
      save_state
      send_claude
    end

    def send_claude
      commit_sha = @state['commits'].last || @repo.head_sha
      @state['next_agent'] = 'claude'
      path = PromptWriter.new(@files, @context, @state).claude_review(@state.fetch('review_iteration'), commit_sha)
      send_prompt(path)
      @state['phase'] = @state['review_iteration'] == 1 ? 'waiting_for_claude' : 'waiting_for_fix_review'
      save_state
    end

    def handle_claude_review
      status = read_status('claude', 'review', @state.fetch('review_iteration'))
      if status['status'] == 'needs_user'
        pause_for_user(status.fetch('question'))
      else
        @state['claude_findings'] = actionable_findings(status['findings'])
        @state['phase'] = 'ready_for_risk_reconciliation'
        save_state
        print_risk_reconciliation_gate
      end
    end

    def send_classify
      path = PromptWriter.new(@files, @context, @state).pi_classify(@state.fetch('review_iteration'), @state.fetch('claude_findings'))
      send_prompt(path)
      @state['phase'] = 'waiting_for_classify'
      save_state
    end

    def handle_classification
      status = read_status('pi', 'classify', @state.fetch('review_iteration'))
      resolutions = status.fetch('resolutions')
      disputes = resolutions.select { |resolution| %w[dispute needs_user].include?(resolution['decision']) }
      accepted = resolutions.select { |resolution| %w[accept accept_with_alternative_fix].include?(resolution['decision']) }
      unless disputes.empty?
        @state['accepted_resolutions'] = accepted
        @state['debate_findings'] = @state.fetch('claude_findings').select { |finding| disputes.any? { |item| item['finding_id'] == finding['id'] } }
        @state['debate_resolutions'] = disputes
        @state['debate_round'] = 1
        @state['phase'] = 'ready_to_send_claude_debate'
        save_state
        return
      end
      if accepted.empty?
        @state['phase'] = 'ready_for_final_checks'
      else
        @state['accepted_resolutions'] = accepted
        @state['fix_iteration'] = (@state['fix_iteration'] || 0) + 1
        @state['phase'] = 'ready_to_send_fix'
      end
      save_state
    end

    def commit_manager_fix
      ensure_clean_before_commit!
      raise Error, 'Pi-worker produced no changes for manager findings' if @repo.clean?

      @repo.add_all
      sha = @repo.commit("Address PR #{@context.pr_number} round #{@state.fetch('current_round')} manager fix #{@state.fetch('manager_fix_iteration')}")
      record_commit(sha)
      @state['review_iteration'] = (@state['review_iteration'] || 0) + 1
      send_claude
    end

    def send_claude_debate
      @state['next_agent'] = 'claude'
      prompt = PromptWriter.new(@files, @context, @state).claude_debate(
        @state.fetch('debate_round'), @state.fetch('debate_findings'), @state.fetch('debate_resolutions')
      )
      send_prompt(prompt)
      @state['phase'] = 'waiting_for_claude_debate'
      save_state
    end

    def handle_claude_debate
      status = read_status('claude', 'debate', @state.fetch('debate_round'))
      debates = Array(status['debates'])
      validate_debate_ids!(debates)
      if debates.any? { |debate| %w[needs_user].include?(debate['decision']) }
        pause_for_user('Claude requested user input during debate. Review the debate status JSON and choose accept or skip for each finding.')
        return
      end

      @state['claude_debates'] = debates
      @state['phase'] = 'ready_to_send_pi_debate'
      save_state
    end

    def send_pi_debate
      prompt = PromptWriter.new(@files, @context, @state).pi_debate(
        @state.fetch('debate_round'), @state.fetch('debate_findings'), @state.fetch('debate_resolutions'), @state.fetch('claude_debates')
      )
      send_prompt(prompt)
      @state['phase'] = 'waiting_for_pi_debate'
      save_state
    end

    def handle_pi_debate
      status = read_status('pi', 'debate', @state.fetch('debate_round'))
      debates = Array(status['debates'])
      validate_debate_ids!(debates)
      if debates.any? { |debate| debate['decision'] == 'needs_user' }
        pause_for_user('Pi requested user input during debate. Review the debate status JSON and choose accept or skip for each finding.')
        return
      end

      accepted = debates.select { |debate| debate['decision'] == 'accept' }
      unresolved = debates.select { |debate| debate['decision'] == 'still_disagree' }
      if unresolved.any? && @state.fetch('debate_round') >= 3
        pause_for_user('Pi and Claude still disagree after the addressit debate limit. Decide whether each disputed finding should be accepted or skipped.')
        return
      end

      @state['accepted_resolutions'] = Array(@state['accepted_resolutions']) + accepted.map do |debate|
        { 'finding_id' => debate['finding_id'], 'decision' => 'accept', 'rationale' => debate['rationale'].to_s }
      end
      if unresolved.empty?
        @state['fix_iteration'] = (@state['fix_iteration'] || 0) + 1 unless @state['accepted_resolutions'].empty?
        @state['phase'] = @state['accepted_resolutions'].empty? ? 'ready_for_final_checks' : 'ready_to_send_fix'
      else
        @state['debate_findings'] = @state.fetch('debate_findings').select { |finding| unresolved.any? { |item| item['finding_id'] == finding['id'] } }
        @state['debate_resolutions'] = unresolved
        @state['debate_round'] += 1
        @state['phase'] = 'ready_to_send_claude_debate'
      end
      save_state
    end

    def validate_debate_ids!(debates)
      expected = @state.fetch('debate_findings').map { |finding| finding['id'] }.sort
      actual = debates.map { |debate| debate['finding_id'].to_s }.sort
      raise Error, 'Debate status must include exactly one decision for every disputed finding' unless actual == expected
    end

    def send_fix
      round_state = @state['rounds'].find { |entry| entry['number'] == @state.fetch('current_round') }
      round_state['baseline_head'] = @repo.head_sha
      findings = @state.fetch('claude_findings')
      path = PromptWriter.new(@files, @context, @state).pi_fix(@state.fetch('fix_iteration'), findings, @state.fetch('accepted_resolutions'))
      send_prompt(path)
      @state['phase'] = 'waiting_for_fix'
      save_state
    end

    def commit_fix
      ensure_clean_before_commit!
      if @repo.clean?
        @state['phase'] = 'ready_for_final_checks'
        save_state
        return
      end

      @repo.add_all
      commit_sha = @repo.commit("Address PR #{@context.pr_number} round #{@state.fetch('current_round')} fix #{@state.fetch('fix_iteration')}")
      record_commit(commit_sha)
      @state['review_iteration'] += 1
      send_claude
    end

    def actionable_findings(findings)
      Array(findings).select { |finding| %w[BLOCKER MINOR].include?(finding['severity']) }
    end

    def require_nonempty_artifact!(path, label)
      return if File.file?(path) && !File.read(path).strip.empty?

      raise Error, "#{label} artifact is missing or empty: #{path}. Agents must write artifacts before status JSON."
    end

    def validate_hypotheses!(data)
      raise Error, 'Manager hypotheses must be a JSON object' unless data.is_a?(Hash)

      hypotheses = data['hypotheses']
      raise Error, 'Manager hypotheses must be a non-empty array' unless hypotheses.is_a?(Array) && !hypotheses.empty?

      ids = hypotheses.map.with_index do |hypothesis, index|
        unless hypothesis.is_a?(Hash)
          raise Error, "Manager hypothesis #{index} must be an object"
        end

        %w[id kind check reason].each do |key|
          unless hypothesis[key].is_a?(String) && !hypothesis[key].strip.empty?
            raise Error, "Manager hypothesis #{index}.#{key} must be a non-empty string"
          end
        end
        hypothesis['id']
      end
      raise Error, 'Manager hypothesis ids must be unique' unless ids.uniq.length == ids.length
    end

    def validate_hypothesis_coverage!(manifest)
      hypotheses = JSON.parse(File.read(@state.fetch('manager_hypotheses_path')))['hypotheses']
      coverage = manifest['hypothesis_coverage']
      raise Error, 'Risk manifest hypothesis_coverage must be a present array' unless coverage.is_a?(Array)

      expected_ids = hypotheses.map { |hypothesis| hypothesis.fetch('id') }
      coverage.each_with_index do |item, index|
        raise Error, "Risk manifest hypothesis_coverage[#{index}] must be an object" unless item.is_a?(Hash)
        unless item['id'].is_a?(String) && !item['id'].strip.empty?
          raise Error, "Risk manifest hypothesis_coverage[#{index}].id must be a non-empty string"
        end
        unless item['status'] == 'covered'
          raise Error, "Risk manifest hypothesis_coverage[#{index}] status must be covered"
        end
        unless item['note'].is_a?(String) && !item['note'].strip.empty?
          raise Error, "Risk manifest hypothesis_coverage[#{index}].note must be a non-empty string"
        end
      end
      actual_ids = coverage.map { |item| item['id'] }
      raise Error, 'Risk manifest hypothesis_coverage must acknowledge every hypothesis exactly once' unless actual_ids.uniq.length == actual_ids.length && actual_ids.sort == expected_ids.sort
    rescue JSON::ParserError => e
      raise Error, "Invalid manager hypotheses JSON: #{e.message}"
    end

    def tagged_findings(findings, prefix)
      Array(findings).map do |finding|
        finding.merge('id' => "#{prefix}-#{finding.fetch('id')}")
      end
    end

    def run_final_checks
      commands = Array(@state.fetch('final_check_commands', []))
      results = commands.map { |command| execute_check(command) }
      File.write(@files.final_checks_path, format_checks(results))
      @state['final_checks'] = results
      if results.all? { |result| result['status'] == 'passed' || result['status'] == 'skipped' }
        @state['phase'] = 'ready_for_manager_review'
        save_state
      else
        pause_for_user("Final checks failed. Read #{@files.final_checks_path} and decide whether to resume with a Pi fix.")
      end
    end

    def execute_check(command)
      result = @shell.capture('bash', '-c', command, chdir: @context.repo_root)
      { 'command' => command, 'status' => result.success? ? 'passed' : 'failed', 'exit_code' => result.status.exitstatus, 'output' => result.stdout + result.stderr }
    end

    def format_checks(results)
      lines = ["# Final checks", "", "Run at: #{Time.now.iso8601}", ""]
      if results.empty?
        lines << 'Skipped: no configured checks.'
      else
        results.each { |result| lines << "## #{result['command']}\n\nStatus: #{result['status']}\n\n```text\n#{result['output']}\n```\n" }
      end
      lines.join("\n")
    end

    def wait_for(agent, phase, iteration = nil)
      print_waiting_stage(agent, phase, iteration)
      status_path = @files.status_path(@state.fetch('current_round'), agent, phase, iteration)
      timeout = @state.fetch('worker_status_timeout_minutes', 10).to_i * 60
      deadline = Time.now + timeout
      until File.file?(status_path)
        raise Error, "Timed out waiting for #{agent} status JSON: #{status_path}" if Time.now >= deadline

        sleep 1
      end
      status = read_status(agent, phase, iteration)
      if status['status'] == 'failed'
        raise Error, "#{agent} failed: #{status['summary']}"
      elsif status['status'] == 'needs_user'
        pause_for_user(status.fetch('question'))
      else
        yield
        save_state
      end
    end

    def print_waiting_stage(agent, phase, iteration)
      stage_name = WAITING_STAGE_NAMES.fetch(@state.fetch('phase')) { "#{agent}:#{phase}".upcase.tr('_', ' ') }
      context = ["Round #{@state.fetch('current_round')}"]
      context << "Iteration #{iteration}" if iteration

      puts
      puts '=================='
      puts "[#{stage_name} — #{context.join(' — ')}]"
      puts '=================='
    end

    def read_status(agent, phase, iteration = nil)
      path = @files.status_path(@state.fetch('current_round'), agent, phase, iteration)
      validator = Autowork::StatusValidator.new
      result = validator.validate_file(path, expected: { 'agent' => agent, 'phase' => phase, 'step' => 0 })
      raise Error, "Invalid worker status #{path}: #{result.errors.join('; ')}" unless result.valid?

      result.data
    end

    def send_prompt(path)
      roles = @tmux.discover_roles(@context.repo_root)
      target = roles.respond_to?(:pi_worker) && @state['next_agent'] == 'claude' ? roles.claude_worker.id : roles.pi_worker.id
      @state['pane_targets'] ||= { 'pi_worker' => roles.pi_worker.id, 'claude_worker' => roles.claude_worker.id }
      target = @state['next_agent'] == 'claude' ? @state['pane_targets']['claude_worker'] : @state['pane_targets']['pi_worker']
      @tmux.send_prompt(target, path)
      @state.delete('next_agent')
    end

    def pause_for_user(question)
      @state['phase'] = 'awaiting_user'
      @state['question'] = question
      save_state
      puts question
    end

    def print_selection(comments, round)
      puts "Addressit round #{round}: #{comments.length} new review item(s)."
      comments.each_with_index do |comment, index|
        location = comment['path'].to_s
        location += ":#{comment['line']}" if comment['line']
        puts "#{index + 1}. @#{comment.dig('user', 'login')} #{location} comment=#{comment['id']} #{comment['html_url']}"
      end
      puts "Full comments: #{@files.comments_path(round)}"
      puts "Write approval JSON to #{@files.approval_path(round)} and run: addressit approve #{@context.task_folder} <approval-json>"
    end

    def print_manager_hypotheses_gate
      round = @state.fetch('current_round')
      puts "Addressit round #{round}: pi-manager must write current-only review hypotheses."
      puts "Do not read historical risk data yet. Write JSON with a hypotheses array to: #{@files.manager_hypotheses_path(round)}"
      puts '{"hypotheses":[{"id":"H1","kind":"...","check":"...","reason":"..."}]}'
      puts "Then run: addressit audit-start #{@context.task_folder} #{@files.manager_hypotheses_path(round)}"
    end

    def print_risk_reconciliation_gate
      round = @state.fetch('current_round')
      registry = File.join(Autowork::TASK_ROOT, @context.project, 'review-risk-registry.json')
      puts "Addressit round #{round}: pi-manager must reconcile blind audits."
      puts "Now read the project risk registry: #{registry}"
      puts "Prioritize active, high-weight risks only when their tags/triggers match this diff."
      puts "Write the final manifest to: #{@files.risk_manifest_path(round)}"
      puts '{"summary":"...","coverage_gaps":[],"hypothesis_coverage":[{"id":"H1","status":"covered","note":"..."}],"additional_findings":[],"registry_updates":[]}'
      puts "Acknowledge every hypothesis exactly once in hypothesis_coverage with status covered and a short note. Resolve every gap; use coverage_gaps: [] only when none remain."
      puts "Then run: addressit audit-reconcile #{@context.task_folder} #{@files.risk_manifest_path(round)}"
    end

    def print_manager_gate
      puts "Addressit is ready for pi-manager review."
      puts "Review diff, comments, audits, risk manifest, checks, and commits; write #{@files.manager_review_path}."
      puts "Then run: addressit manager-pass #{@context.task_folder}"
    end

    def ensure_clean_before_commit!
      round_state = @state['rounds'].find { |entry| entry['number'] == @state.fetch('current_round') }
      expected_head = round_state['baseline_head']
      return if expected_head.nil? || @repo.head_sha == expected_head

      raise Error, "HEAD changed while addressit was waiting for the worker: expected #{expected_head}, got #{@repo.head_sha}"
    end

    def save_state
      Store.new(@files.state_path).write(@state)
    end
  end

  class CLI
    def initialize(argv, cwd: Dir.pwd)
      @argv = argv.dup
      @cwd = cwd
      @task_id = extract_task_id!
    end

    def run
      command = @argv.first
      case command
      when 'approve'
        approve
      when 'audit-start'
        audit_start
      when 'audit-reconcile'
        audit_reconcile
      when 'manager-pass'
        manager_pass
      when 'manager-fix'
        manager_fix
      when 'resolve'
        resolve_user
      when 'status'
        status
      else
        start_or_resume
      end
    rescue Autowork::Error, Error => e
      warn "addressit: #{e.message}"
      1
    end

    private

    def extract_task_id!
      @review_clipboard = !!@argv.delete('--clipboard')
      index = @argv.index('--task')
      return unless index

      task_id = @argv[index + 1]
      raise Error, 'Usage: addressit <pr-number-or-github-url> [filters] [--task <local-task-id>]' unless task_id&.match?(/\A\d+\z/)

      @argv.slice!(index, 2)
      task_id
    end

    def review_source
      @review_clipboard ? ClipboardReview.new : GitHub.new(@argv)
    end

    def resolve_context
      TaskResolver.new(cwd: @cwd).resolve(task_id: @task_id)
    end

    def files_and_state(context)
      files = Files.new(context.task_folder)
      files.mkdirs
      raise Error, "Missing addressit state: #{files.state_path}" unless File.file?(files.state_path)
      [files, Store.new(files.state_path).read]
    end

    def start_or_resume
      context = resolve_context
      files = Files.new(context.task_folder)
      is_new_run = !File.file?(files.state_path)
      Autowork::TaskRepoSnapshot.commit!(context.task_folder) if is_new_run
      files.mkdirs
      state = if File.file?(files.state_path)
                Store.new(files.state_path).read
              else
                repo, number = if @review_clipboard
                  [nil, nil]
                else
                  github = GitHub.new(@argv)
                  [github.repo, github.number]
                end
                final_commands = File.file?(File.join(context.repo_root, 'Gemfile')) ? ['bundle exec rubocop', 'bundle exec rspec'] : []
                initial_state(context, repo, number, final_commands)
              end
      write_config(files, state) unless File.file?(files.config_path)
      if state['pr_repo'] && !@review_clipboard
        # Existing state owns the PR target; reruns must not silently switch PRs.
        requested = GitHub.new(@argv)
        unless requested.repo == state['pr_repo'] && requested.number.to_s == state['pr_number'].to_s
          raise Error, 'PR target does not match existing addressit run'
        end
      end
      raise Error, "Addressit task is tied to branch #{state['branch_name'].inspect}, currently on #{context.branch.inspect}" if state['branch_name'] && state['branch_name'] != context.branch

      state['repo_root'] = context.repo_root
      state['branch_name'] = context.branch
      context.pr_repo = state['pr_repo']
      context.pr_number = state['pr_number']
      Store.new(files.state_path).write(state)
      lock = Lock.new(files.lock_path)
      lock.acquire!
      begin
        if %w[complete no_new_comments round_skipped].include?(state['phase'])
          state['phase'] = 'ready_to_fetch'
          Store.new(files.state_path).write(state)
          Orchestrator.new(context, files, state).prepare_round!(review_source)
        elsif state['phase'] == 'ready_to_fetch'
          Orchestrator.new(context, files, state).prepare_round!(review_source)
        else
          Orchestrator.new(context, files, state).run
        end
      ensure
        lock.release
      end
      0
    end

    def approve
      task_folder, approval_path = @argv[1], @argv[2]
      raise Error, 'Usage: addressit approve <task_folder> <approval-json>' unless task_folder && approval_path
      context, files, state = load_by_task(task_folder)
      lock = Lock.new(files.lock_path)
      lock.acquire!
      begin
        Orchestrator.new(context, files, state).approve!(approval_path)
      ensure
        lock.release
      end
      0
    end

    def audit_start
      task_folder, hypotheses_path = @argv[1], @argv[2]
      raise Error, 'Usage: addressit audit-start <task_folder> <hypotheses-json>' unless task_folder && hypotheses_path
      context, files, state = load_by_task(task_folder)
      lock = Lock.new(files.lock_path)
      lock.acquire!
      begin
        Orchestrator.new(context, files, state).start_audit!(hypotheses_path)
      ensure
        lock.release
      end
      0
    end

    def audit_reconcile
      task_folder, manifest_path = @argv[1], @argv[2]
      raise Error, 'Usage: addressit audit-reconcile <task_folder> <manifest-json>' unless task_folder && manifest_path
      context, files, state = load_by_task(task_folder)
      lock = Lock.new(files.lock_path)
      lock.acquire!
      begin
        Orchestrator.new(context, files, state).reconcile_audit!(manifest_path)
      ensure
        lock.release
      end
      0
    end

    def manager_fix
      task_folder, findings_path = @argv[1], @argv[2]
      raise Error, 'Usage: addressit manager-fix <task_folder> <findings-json>' unless task_folder && findings_path
      context, files, state = load_by_task(task_folder)
      lock = Lock.new(files.lock_path)
      lock.acquire!
      begin
        Orchestrator.new(context, files, state).manager_fix!(findings_path)
      ensure
        lock.release
      end
      0
    end

    def resolve_user
      task_folder, resolution_path = @argv[1], @argv[2]
      raise Error, 'Usage: addressit resolve <task_folder> <resolution-json>' unless task_folder && resolution_path
      context, files, state = load_by_task(task_folder)
      lock = Lock.new(files.lock_path)
      lock.acquire!
      begin
        Orchestrator.new(context, files, state).resolve_user!(resolution_path)
      ensure
        lock.release
      end
      0
    end

    def manager_pass
      task_folder = @argv[1]
      raise Error, 'Usage: addressit manager-pass <task_folder>' unless task_folder
      context, files, state = load_by_task(task_folder)
      lock = Lock.new(files.lock_path)
      lock.acquire!
      begin
        Orchestrator.new(context, files, state).manager_pass!
      ensure
        lock.release
      end
      0
    end

    def status
      task_folder = @argv[1]
      raise Error, 'Usage: addressit status <task_folder>' unless task_folder
      files = Files.new(task_folder)
      puts File.read(files.state_path)
      0
    end

    def load_by_task(task_folder)
      task_folder = File.realpath(task_folder)
      files = Files.new(task_folder)
      state = Store.new(files.state_path).read
      context = Context.new(
        project: state['project'], task_id: state['task_id'], task_folder: task_folder,
        repo_root: state['repo_root'], branch: state['branch_name'], pr_repo: state['pr_repo'], pr_number: state['pr_number']
      )
      [context, files, state]
    end

    def write_config(files, state)
      File.write(files.config_path, {
        'task_folder' => state['task_folder'],
        'repo_dir' => state['repo_root'],
        'branch_name' => state['branch_name'],
        'pr_repo' => state['pr_repo'],
        'pr_number' => state['pr_number'],
        'final_check_commands' => state['final_check_commands'],
        'worker_status_timeout_minutes' => state['worker_status_timeout_minutes'],
        'max_fix_iterations' => state['max_fix_iterations'],
        'max_total_commits' => state['max_total_commits']
      }.to_yaml)
    end

    def initial_state(context, repo, number, final_commands)
      {
        'version' => 1,
        'project' => context.project,
        'task_id' => context.task_id,
        'task_folder' => context.task_folder,
        'repo_root' => context.repo_root,
        'branch_name' => context.branch,
        'pr_repo' => repo,
        'pr_number' => number&.to_i,
        'phase' => 'ready_to_fetch',
        'rounds' => [],
        'comment_ledger' => [],
        'commits' => [],
        'final_check_commands' => final_commands,
        'worker_status_timeout_minutes' => 10,
        'max_fix_iterations' => DEFAULT_MAX_FIX_ITERATIONS,
        'max_total_commits' => DEFAULT_MAX_TOTAL_COMMITS,
        'created_at' => Time.now.iso8601
      }
    end
  end
end
