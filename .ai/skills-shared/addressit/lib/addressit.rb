# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'json'
require 'time'

require_relative '../../autowork/lib/autowork'

module Addressit
  class Error < StandardError; end

  TASK_ROOT = '/Volumes/dev/_tasks'
  DOTS_REPO = '/Users/inseybo/.dots'
  WORKER_STATUS_TIMEOUT_SECONDS = 600
  REVIEW_AGENTS = %w[claude codex].freeze
  DEFAULT_REVIEW_AGENT = 'codex'
  CURRENT_ROUND_STATE_KEYS = %w[
    current_round
    baseline_head
    round_start_head
    commit_shas
    review_iteration
    fix_iteration
    manager_fix_iteration
    debate_round
    question
  ].freeze
  OBSOLETE_STATE_KEYS = %w[
    claude_findings
    claude_manual_verification_findings
    claude_debates
    pi_audit_findings
    pi_manual_verification_findings
    reviewer_findings
    reviewer_manual_verification_findings
    audit_findings
    manual_verification_findings
    accepted_resolutions
    debate_findings
    debate_resolutions
    reviewer_debates
    manager_findings
    final_checks
    manager_hypotheses_path
    risk_manifest_path
    risk_reconciliation_path
    next_agent
    pane_targets
  ].freeze
  LEGACY_REVIEW_PHASES = {
    'ready_to_send_claude' => 'ready_to_send_reviewer',
    'waiting_for_claude' => 'waiting_for_reviewer',
    'ready_to_send_claude_debate' => 'ready_to_send_reviewer_debate',
    'waiting_for_claude_debate' => 'waiting_for_reviewer_debate'
  }.freeze
  REVIEW_AGENT_CHANGE_PHASES = %w[
    ready_to_fetch
    awaiting_round_approval
    ready_to_send_pi
    waiting_for_pi
    ready_to_commit
    ready_for_manager_hypotheses
    ready_to_send_pi_audit
    waiting_for_pi_audit
    ready_to_send_reviewer
    no_new_comments
    round_skipped
    complete
  ].freeze

  # Separates findings that can enter automatic fixes from those requiring operator evidence review.
  class FindingEvidence
    REACHABILITY_SOURCES = %w[
      task_acceptance_criterion
      production_caller
      test_reproduction
      provider_documentation
      observed_runtime_data
      normal_execution_path
    ].freeze
    REQUIRED_FIELDS = %w[trigger mechanism evidence].freeze

    def self.partition(findings)
      relevant = Array(findings).filter { |finding| %w[BLOCKER MINOR].include?(finding['severity']) }
      actionable, manual = relevant.partition { |finding| actionable?(finding) }
      [actionable, manual.map { |finding| mark_for_manual_verification(finding) }]
    end

    def self.actionable?(finding)
      return false unless finding['verification'] == 'actionable'
      return false unless REACHABILITY_SOURCES.include?(finding['reachability_source'])

      REQUIRED_FIELDS.all? { |field| nonempty_string?(finding[field]) }
    end

    def self.mark_for_manual_verification(finding)
      finding.merge(
        'verification' => 'needs_context',
        'missing_evidence' => missing_evidence(finding)
      )
    end

    def self.missing_evidence(finding)
      return finding['missing_evidence'].strip if nonempty_string?(finding['missing_evidence'])

      missing = REQUIRED_FIELDS.reject { |field| nonempty_string?(finding[field]) }
      missing << 'accepted reachability_source' unless REACHABILITY_SOURCES.include?(finding['reachability_source'])
      missing.empty? ? 'The reviewer did not mark this finding actionable.' : "Missing #{missing.join(', ')}."
    end

    def self.nonempty_string?(value)
      value.is_a?(String) && !value.strip.empty?
    end

    private_class_method :mark_for_manual_verification, :missing_evidence, :nonempty_string?
  end

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
    def resolutions_path(round) = round_path(round, 'resolutions.json')

    def review_path(round, iteration)
      neutral = File.join(log_dir, 'reviews', "round#{round}_reviewer_review#{iteration}.md")
      legacy = File.join(log_dir, 'reviews', "round#{round}_claude_review#{iteration}.md")
      File.file?(legacy) ? legacy : neutral
    end

    def audit_path(round, agent) = File.join(log_dir, 'audits', "round#{round}_#{agent}_blind_audit.md")
    def manager_hypotheses_path(round) = File.join(log_dir, 'audits', "round#{round}_manager_initial_review_hypotheses.json")
    def risk_manifest_path(round) = File.join(log_dir, 'audits', "round#{round}_risk_coverage_manifest.json")
    def reconciliation_path(round) = File.join(log_dir, 'audits', "round#{round}_risk_reconciliation.json")
    def manual_verification_path(round) = File.join(log_dir, 'audits', "round#{round}_manual_verification.json")

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
      File.write(@path, JSON.pretty_generate(data) + "\n")
    end
  end

  class Lock
    def initialize(path)
      @path = path
    end

    def acquire!
      FileUtils.mkdir_p(File.dirname(@path))
      @file = File.open(@path, File::RDWR | File::CREAT, 0o644)
      return write_owner_pid if @file.flock(File::LOCK_EX | File::LOCK_NB)

      @file.close
      @file = nil
      raise Error, "Addressit is already running: #{@path}"
    end

    def release
      file, @file = @file, nil
      return unless file

      file.flock(File::LOCK_UN)
      file.close
    end

    private

    def write_owner_pid
      @file.rewind
      @file.truncate(0)
      @file.write("#{Process.pid}\n")
      @file.flush
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
      [{
        'id' => id,
        'kind' => 'local_review',
        'path' => nil,
        'line' => nil,
        'body' => text,
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
        'created_at' => comment['created_at'] || comment['submitted_at']
      ).tap { |normalized| normalized.delete('updated_at') }
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
      comments.select { |comment| Time.parse(comment['created_at']) >= threshold }
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

        You are the Pi implementation agent participating in `/addressit` as `agent-worker`.
        Work only in #{@context.repo_root}.

        Read:
        - task: #{@context.task_folder}/task.md
        - comments: #{@files.comments_path(round)}
        - approval: #{@files.approval_path(round)}
        - addressit state: #{@files.state_path}

        If task.md starts with the exact Feature reference from the shared task-resolution rules, read the linked Feature file before task.md. Use its goal, scope, and shared constraints as background; let task.md win conflicts and ignore the Feature inventory.

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

        You are the Pi review agent participating in `/addressit` as `agent-worker`.
        Review the complete current diff in #{@context.repo_root} after the implementation commit.

        Read:
        - task: #{@context.task_folder}/task.md
        - addressit state: #{@files.state_path}

        If task.md starts with the exact Feature reference from the shared task-resolution rules, read the linked Feature file before task.md. Use its goal, scope, and shared constraints as background; let task.md win conflicts and ignore the Feature inventory.

        This is an independent discovery pass. Do not read manager hypotheses, historical risk files, or other audit artifacts. Do not edit files and do not run tests, linters, or formatters.

        Look for correctness, concurrency, idempotency, external-boundary, partial-failure, data-integrity, time/identity, and operator-behavior risks that the implementation introduced. Do not limit the review to the approved comments.

        A finding is actionable only when you can state its trigger, failure mechanism, accepted reachability source, and concrete evidence. Accepted reachability sources are: task_acceptance_criterion, production_caller, test_reproduction, provider_documentation, observed_runtime_data, and normal_execution_path. Tests that only prove isolated behavior are not production reachability evidence.

        If reachability cannot be established, keep the finding but use verification `needs_context` and state the missing evidence. Addressit routes it to operator verification instead of the automatic fix loop.

        Write the concise human-readable audit to #{audit}. Write valid status JSON last to #{status}, then stop immediately.
        Required status shape:
        {"status":"done","agent":"pi","phase":"audit","step":0,"summary":"...","findings":[{"id":"P1","severity":"BLOCKER|MINOR","title":"...","body":"...","verification":"actionable|needs_context","trigger":"...","mechanism":"...","reachability_source":"normal_execution_path","evidence":"...","missing_evidence":"required when verification is needs_context"}]}
        Use an empty findings array when no findings remain. Use status `needs_user` with a question only when input is required for the review itself.
      PROMPT
      path
    end

    def reviewer_review(iteration, commit_sha)
      round = @state.fetch('current_round')
      agent = @state.fetch('review_agent')
      path = @files.prompt_path("round#{round}_reviewer_review#{iteration}_request.md")
      status = @files.status_path(round, agent, 'review', iteration)
      review = @files.review_path(round, iteration)
      FileUtils.rm_f(status)
      FileUtils.rm_f(review)
      File.write(path, <<~PROMPT)
        # Addressit: review round #{round}, iteration #{iteration}

        You are the #{agent.capitalize} review agent participating in `/addressit` as `agent-reviewer`.
        Review commit #{commit_sha} in #{@context.repo_root}.

        Read:
        - task: #{@context.task_folder}/task.md
        - comments: #{@files.comments_path(round)}
        - approval: #{@files.approval_path(round)}
        - addressit state: #{@files.state_path}

        If task.md starts with the exact Feature reference from the shared task-resolution rules, read the linked Feature file before task.md. Use its goal, scope, and shared constraints as background; let task.md win conflicts and ignore the Feature inventory.

        Review every approved comment and the complete current diff, not only the comment locations. Independently look for correctness, concurrency, idempotency, external-boundary, partial-failure, data-integrity, time/identity, and operator-behavior risks. Do not read manager hypotheses, historical risk files, or Pi's blind audit. Do not edit files and do not run tests, linters, or formatters. Use read-only inspection and Pi's reported checks.

        A finding is actionable only when you can state its trigger, failure mechanism, accepted reachability source, and concrete evidence. Accepted reachability sources are: task_acceptance_criterion, production_caller, test_reproduction, provider_documentation, observed_runtime_data, and normal_execution_path. Tests that only prove isolated behavior are not production reachability evidence.

        If reachability cannot be established, keep the finding but use verification `needs_context` and state the missing evidence. Addressit routes it to operator verification instead of the automatic fix loop.

        Write the full human-readable review to #{review} before the status JSON.
        Write valid status JSON last to #{status}, then stop immediately.

        Required status shape:
        {"status":"done","agent":"#{agent}","phase":"review","step":0,"summary":"...","findings":[{"id":"F1","severity":"BLOCKER|MINOR","title":"...","body":"...","verification":"actionable|needs_context","trigger":"...","mechanism":"...","reachability_source":"production_caller","evidence":"...","missing_evidence":"required when verification is needs_context"}]}
        Use an empty findings array when the commit is accepted. Use status `needs_user` with a question only when input is required for the review itself.
        PROMPT
      path
    end

    def pi_classify(iteration, findings)
      round = @state.fetch('current_round')
      path = @files.prompt_path("round#{round}_pi_classify#{iteration}_request.md")
      status = @files.status_path(round, 'pi', 'classify', iteration)
      FileUtils.rm_f(status)
      File.write(path, <<~PROMPT)
        # Addressit: classify reviewer findings for round #{round}

        You are the Pi implementation agent participating in `/addressit` as `agent-worker`.
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

    def reviewer_debate(iteration, findings, resolutions)
      round = @state.fetch('current_round')
      agent = @state.fetch('review_agent')
      path = @files.prompt_path("round#{round}_reviewer_debate#{iteration}_request.md")
      status = @files.status_path(round, agent, 'debate', iteration)
      FileUtils.rm_f(status)
      File.write(path, <<~PROMPT)
        # Addressit: debate disputed findings for round #{round}

        You are the #{agent.capitalize} review agent participating in `/addressit` as `agent-reviewer`.
        Do not edit files or run checks. Reconsider these disputed findings using Pi's rationale:

        Findings:
        #{JSON.pretty_generate(findings)}

        Pi resolutions:
        #{JSON.pretty_generate(resolutions)}

        For every finding, choose one decision: `accept`, `agree_with_pi`, `still_disagree`, or `needs_user`.
        Write valid status JSON last to #{status}, then stop immediately.
        Required shape:
        {"status":"done","agent":"#{agent}","phase":"debate","step":0,"summary":"...","debates":[{"finding_id":"F1","decision":"accept","rationale":"..."}]}
        PROMPT
      path
    end

    def pi_debate(iteration, findings, resolutions, reviewer_debates)
      round = @state.fetch('current_round')
      path = @files.prompt_path("round#{round}_pi_debate#{iteration}_request.md")
      status = @files.status_path(round, 'pi', 'debate', iteration)
      FileUtils.rm_f(status)
      File.write(path, <<~PROMPT)
        # Addressit: resolve disputed findings for round #{round}

        You are the Pi implementation agent participating in `/addressit` as `agent-worker`.
        Do not edit files in this turn.

        Reconsider each disputed finding after the reviewer's response.
        Findings:
        #{JSON.pretty_generate(findings)}

        Original Pi resolutions:
        #{JSON.pretty_generate(resolutions)}

        Reviewer debate response:
        #{JSON.pretty_generate(reviewer_debates)}

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
        # Addressit: fix agent-manager findings for round #{round}

        You are the Pi implementation agent participating in `/addressit` as `agent-worker`.
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

        You are the Pi implementation agent participating in `/addressit` as `agent-worker`.
        Work only in #{@context.repo_root}. Do not commit or stage changes.

        Fix only these accepted reviewer findings:
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
      'waiting_for_reviewer' => 'REVIEWER REVIEW',
      'waiting_for_fix_review' => 'REVIEWER FIX REVIEW',
      'waiting_for_classify' => 'PI FINDING CLASSIFICATION',
      'waiting_for_reviewer_debate' => 'REVIEWER DEBATE',
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
      terminal_ids = Array(@state['addressed_ids']) + Array(@state['skipped_ids'])
      candidates = comments.reject { |comment| terminal_ids.include?(comment['id'].to_s) }
      clear_current_round!
      round = next_round_number
      File.write(@files.comments_path(round), JSON.pretty_generate(candidates) + "\n")
      @state.merge!(
        'current_round' => round,
        'baseline_head' => @repo.head_sha,
        'round_start_head' => @repo.head_sha,
        'commit_shas' => [],
        'phase' => candidates.empty? ? 'no_new_comments' : 'awaiting_round_approval'
      )
      print_selection(candidates, round)
      clear_current_round! if candidates.empty?
      save_state
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

      approved = []
      skipped = []
      comments.each do |comment|
        item = decisions.fetch(comment['id'].to_s)
        decision = item['decision'].to_s
        raise Error, "Invalid decision for comment #{comment['id']}: #{decision.inspect}" unless %w[approved skipped].include?(decision)

        decision == 'approved' ? approved << comment['id'].to_s : skipped << comment['id'].to_s
      end
      @state['skipped_ids'] = (Array(@state['skipped_ids']) + skipped).uniq
      destination = @files.approval_path(round)
      FileUtils.cp(approval_path, destination) unless File.expand_path(approval_path) == File.expand_path(destination)
      @state['phase'] = approved.empty? ? 'round_skipped' : 'ready_to_send_pi'
      clear_current_round! if approved.empty?
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
        when 'ready_to_send_reviewer'
          send_reviewer
        when 'ready_for_risk_reconciliation'
          print_risk_reconciliation_gate
          return
        when 'waiting_for_manager_fix'
          wait_for('pi', 'manager_fix', @state.fetch('manager_fix_iteration')) { commit_manager_fix }
        when 'ready_to_commit'
          commit_implementation
        when 'waiting_for_reviewer'
          wait_for(review_agent, 'review', @state.fetch('review_iteration')) { handle_reviewer_review }
        when 'ready_to_send_classify'
          send_classify
        when 'waiting_for_classify'
          wait_for('pi', 'classify', @state.fetch('review_iteration')) { handle_classification }
        when 'ready_to_send_reviewer_debate'
          send_reviewer_debate
        when 'waiting_for_reviewer_debate'
          wait_for(review_agent, 'debate', @state.fetch('debate_round')) { handle_reviewer_debate }
        when 'ready_to_send_pi_debate'
          send_pi_debate
        when 'waiting_for_pi_debate'
          wait_for('pi', 'debate', @state.fetch('debate_round')) { handle_pi_debate }
        when 'ready_to_send_fix'
          send_fix
        when 'waiting_for_fix'
          wait_for('pi', 'fix', @state.fetch('fix_iteration')) { commit_fix }
        when 'waiting_for_fix_review'
          wait_for(review_agent, 'review', @state.fetch('review_iteration')) { handle_reviewer_review }
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
      save_state
      run
    rescue JSON::ParserError => e
      raise Error, "Invalid manager hypotheses JSON: #{e.message}"
    end

    def reconcile_audit!(manifest_path)
      manifest = validated_risk_manifest(manifest_path)
      persist_risk_manifest(manifest_path)
      findings, manual = reconciled_findings(manifest)
      write_risk_reconciliation(manifest, findings, manual)
      resume_after_risk_reconciliation
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
      @state['baseline_head'] = @repo.head_sha
      FileUtils.cp(findings_path, @files.manager_findings_path) unless File.expand_path(findings_path) == File.expand_path(@files.manager_findings_path)
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
      finding_ids = manual_verification_payload.fetch('findings').map { |finding| finding['id'] }
      decisions = resolutions.to_h { |resolution| [resolution['finding_id'].to_s, resolution] }
      raise Error, 'User resolution must classify every reviewer finding' unless decisions.keys.sort == finding_ids.sort

      invalid = resolutions.reject { |resolution| %w[accept skip].include?(resolution['decision']) }
      raise Error, "Invalid user resolution decision(s): #{invalid.map { |item| item['decision'] }.uniq.join(', ')}" unless invalid.empty?

      accepted = resolutions.select { |resolution| resolution['decision'] == 'accept' }
      write_resolutions(
        'accepted_resolutions' => accepted.map do |resolution|
          { 'finding_id' => resolution['finding_id'], 'decision' => 'accept', 'rationale' => resolution['rationale'].to_s }
        end,
        'debate_findings' => [],
        'debate_resolutions' => []
      )
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
      manifest = nil
      if approved_comment_ids(round).any?
        raise Error, "Complete risk reconciliation before passing manager review: #{@files.risk_manifest_path(round)}" unless File.file?(@files.risk_manifest_path(round)) && File.file?(@files.reconciliation_path(round))
        manifest = Autowork::ReviewRiskManifest.validate_file(@files.risk_manifest_path(round))
        raise Error, 'Risk reconciliation has unresolved coverage gaps' unless Array(manifest['coverage_gaps']).empty?
      end
      squash_round_commits!
      Autowork::ReviewRiskRegistry.new(@context.project).apply!(
        Array(manifest && manifest['registry_updates']),
        task_id: @context.task_id,
        round_id: "addressit-#{round}",
      ) if manifest
      addressed_ids = approved_comment_ids(round)
      @state['addressed_ids'] = (Array(@state['addressed_ids']) + addressed_ids).uniq
      @state['phase'] = 'complete'
      clear_current_round!
      save_state
      puts "Addressit round #{round} complete. Marked #{addressed_ids.length} comment(s) addressed."
    end

    private

    def approved_comment_ids(round)
      approval = JSON.parse(File.read(@files.approval_path(round)))
      Array(approval['comments']).filter_map do |comment|
        comment['id'].to_s if comment['decision'] == 'approved'
      end
    end

    def send_pi
      path = PromptWriter.new(@files, @context, @state).pi_implement
      send_prompt(path)
      @state['phase'] = 'waiting_for_pi'
      save_state
    end

    def record_commit(commit_sha)
      @state['commit_shas'] ||= []
      @state['commit_shas'] << commit_sha
    end

    def clear_current_round!
      CURRENT_ROUND_STATE_KEYS.each { |key| @state.delete(key) }
    end

    def next_round_number
      [latest_artifact_round_number, latest_review_update_number].max + 1
    end

    def latest_artifact_round_number
      Dir.glob(@files.round_path('*', 'comments.json')).filter_map do |path|
        File.basename(path)[/\Around(\d+)_comments\.json\z/, 1]&.to_i
      end.max || 0
    end

    def next_final_commit_number
      [@state.fetch('current_round'), latest_review_update_number + 1].max
    end

    def latest_review_update_number
      result = @shell.capture('git', '-C', @context.repo_root, 'log', '--first-parent', '--format=%s')
      return 0 unless result.success?

      result.stdout.lines.filter_map { |subject| subject[/\AAdd review updates (\d+)\s*\z/, 1]&.to_i }.max || 0
    end

    def squash_round_commits!
      commit_shas = Array(@state['commit_shas'])
      raise Error, 'Cannot finalize review round without recorded commits' if commit_shas.empty?

      message = "Add review updates #{next_final_commit_number}"
      @state['commit_shas'] = [@repo.squash_commits(@state.fetch('round_start_head'), message)]
    end

    def commit_implementation
      ensure_clean_before_commit!
      raise Error, 'agent-worker reported completion but produced no repository changes' if @repo.clean?

      @repo.add_all
      commit_sha = @repo.commit("Address PR #{@context.pr_number} round #{@state.fetch('current_round')}")
      record_commit(commit_sha)
      @state['review_iteration'] = 1
      @state['phase'] = 'ready_for_manager_hypotheses'
      save_state
      print_manager_hypotheses_gate
    end

    def send_pi_audit
      path = PromptWriter.new(@files, @context, @state).pi_blind_audit
      send_prompt(path)
      @state['phase'] = 'waiting_for_pi_audit'
      save_state
    end

    def handle_pi_audit
      status = read_status('pi', 'audit')
      require_nonempty_artifact!(@files.audit_path(@state.fetch('current_round'), 'pi'), 'Pi blind audit')
      @state['phase'] = 'ready_to_send_reviewer'
      save_state
      send_reviewer
    end

    def send_reviewer
      commit_sha = Array(@state['commit_shas']).last || @repo.head_sha
      path = PromptWriter.new(@files, @context, @state).reviewer_review(@state.fetch('review_iteration'), commit_sha)
      send_prompt(path, role: :reviewer)
      @state['phase'] = @state['review_iteration'] == 1 ? 'waiting_for_reviewer' : 'waiting_for_fix_review'
      save_state
    end

    def handle_reviewer_review
      status = read_status(review_agent, 'review', @state.fetch('review_iteration'))
      if status['status'] == 'needs_user'
        pause_for_user(status.fetch('question'))
      else
        @state['phase'] = 'ready_for_risk_reconciliation'
        save_state
        print_risk_reconciliation_gate
      end
    end

    def send_classify
      path = PromptWriter.new(@files, @context, @state).pi_classify(@state.fetch('review_iteration'), review_findings)
      send_prompt(path)
      @state['phase'] = 'waiting_for_classify'
      save_state
    end

    def handle_classification
      status = read_status('pi', 'classify', @state.fetch('review_iteration'))
      resolutions = status.fetch('resolutions')
      disputes = resolutions.select { |resolution| %w[dispute needs_user].include?(resolution['decision']) }
      accepted = resolutions.select { |resolution| %w[accept accept_with_alternative_fix].include?(resolution['decision']) }
      disputed_findings = review_findings.select do |finding|
        disputes.any? { |resolution| resolution['finding_id'] == finding['id'] }
      end
      write_resolutions(
        'accepted_resolutions' => accepted,
        'debate_findings' => disputed_findings,
        'debate_resolutions' => disputes
      )
      unless disputes.empty?
        @state['debate_round'] = 1
        @state['phase'] = 'ready_to_send_reviewer_debate'
        save_state
        return
      end
      if accepted.empty?
        @state['phase'] = 'ready_for_final_checks'
      else
        @state['fix_iteration'] = (@state['fix_iteration'] || 0) + 1
        @state['phase'] = 'ready_to_send_fix'
      end
      save_state
    end

    def commit_manager_fix
      ensure_clean_before_commit!
      raise Error, 'agent-worker produced no changes for manager findings' if @repo.clean?

      @repo.add_all
      sha = @repo.commit("Address PR #{@context.pr_number} round #{@state.fetch('current_round')} manager fix #{@state.fetch('manager_fix_iteration')}")
      record_commit(sha)
      @state['review_iteration'] = (@state['review_iteration'] || 0) + 1
      send_reviewer
    end

    def send_reviewer_debate
      resolutions = resolution_data
      prompt = PromptWriter.new(@files, @context, @state).reviewer_debate(
        @state.fetch('debate_round'), resolutions.fetch('debate_findings'), resolutions.fetch('debate_resolutions')
      )
      send_prompt(prompt, role: :reviewer)
      @state['phase'] = 'waiting_for_reviewer_debate'
      save_state
    end

    def handle_reviewer_debate
      status = read_status(review_agent, 'debate', @state.fetch('debate_round'))
      debates = Array(status['debates'])
      validate_debate_ids!(debates)
      if debates.any? { |debate| %w[needs_user].include?(debate['decision']) }
        pause_for_user('The reviewer requested user input during debate. Review the debate status JSON and choose accept or skip for each finding.')
        return
      end

      @state['phase'] = 'ready_to_send_pi_debate'
      save_state
    end

    def send_pi_debate
      round = @state.fetch('debate_round')
      resolutions = resolution_data
      reviewer_debates = read_status(review_agent, 'debate', round).fetch('debates')
      prompt = PromptWriter.new(@files, @context, @state).pi_debate(
        round, resolutions.fetch('debate_findings'), resolutions.fetch('debate_resolutions'), reviewer_debates
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
        pause_for_user('Pi and the reviewer still disagree after the addressit debate limit. Decide whether each disputed finding should be accepted or skipped.')
        return
      end

      resolutions = resolution_data
      accepted_resolutions = resolutions.fetch('accepted_resolutions') + accepted.map do |debate|
        { 'finding_id' => debate['finding_id'], 'decision' => 'accept', 'rationale' => debate['rationale'].to_s }
      end
      unresolved_findings = resolutions.fetch('debate_findings').select do |finding|
        unresolved.any? { |item| item['finding_id'] == finding['id'] }
      end
      write_resolutions(
        'accepted_resolutions' => accepted_resolutions,
        'debate_findings' => unresolved_findings,
        'debate_resolutions' => unresolved
      )
      if unresolved.empty?
        @state['fix_iteration'] = (@state['fix_iteration'] || 0) + 1 unless accepted_resolutions.empty?
        @state['phase'] = accepted_resolutions.empty? ? 'ready_for_final_checks' : 'ready_to_send_fix'
      else
        @state['debate_round'] += 1
        @state['phase'] = 'ready_to_send_reviewer_debate'
      end
      save_state
    end

    def validate_debate_ids!(debates)
      expected = resolution_data.fetch('debate_findings').map { |finding| finding['id'] }.sort
      actual = debates.map { |debate| debate['finding_id'].to_s }.sort
      raise Error, 'Debate status must include exactly one decision for every disputed finding' unless actual == expected
    end

    def send_fix
      @state['baseline_head'] = @repo.head_sha
      resolutions = resolution_data
      path = PromptWriter.new(@files, @context, @state).pi_fix(
        @state.fetch('fix_iteration'), review_findings, resolutions.fetch('accepted_resolutions')
      )
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
      send_reviewer
    end

    def validated_risk_manifest(path)
      unless @state['phase'] == 'ready_for_risk_reconciliation'
        raise Error, "Addressit is not waiting for risk reconciliation (phase #{@state['phase']})"
      end

      manifest = Autowork::ReviewRiskManifest.validate_file(path)
      validate_hypothesis_coverage!(manifest)
      raise Error, 'Risk reconciliation has unresolved coverage gaps' unless manifest['coverage_gaps'].empty?

      manifest
    end

    def persist_risk_manifest(source)
      destination = @files.risk_manifest_path(@state.fetch('current_round'))
      FileUtils.cp(source, destination) unless File.expand_path(source) == File.expand_path(destination)
    end

    def reconciled_findings(manifest)
      additional, additional_manual = FindingEvidence.partition(manifest['additional_findings'])
      pi, pi_manual = initial_audit_findings
      reviewer, reviewer_manual = reviewer_review_findings
      findings = tagged_findings(pi, 'PI') + tagged_findings(reviewer, review_agent.upcase) + additional
      manual = tagged_findings(pi_manual, 'PI') + tagged_findings(reviewer_manual, review_agent.upcase) + additional_manual
      [findings.uniq { |finding| finding['id'] }, manual.uniq { |finding| finding['id'] }]
    end

    def initial_audit_findings
      return [[], []] unless @state.fetch('review_iteration', 1) == 1

      FindingEvidence.partition(read_status('pi', 'audit')['findings'])
    end

    def reviewer_review_findings
      status = read_status(review_agent, 'review', @state.fetch('review_iteration'))
      FindingEvidence.partition(status['findings'])
    end

    def resume_after_risk_reconciliation
      data = reconciliation_data
      return pause_for_evidence_verification unless data.fetch('manual_verification_findings').empty?

      @state['phase'] = data.fetch('findings').empty? ? 'ready_for_final_checks' : 'ready_to_send_classify'
      save_state
      run
    end

    def write_risk_reconciliation(manifest, findings, manual)
      data = {
        'summary' => manifest['summary'],
        'coverage_gaps' => manifest['coverage_gaps'],
        'findings' => findings,
        'manual_verification_findings' => manual
      }
      File.write(@files.reconciliation_path(@state.fetch('current_round')), "#{JSON.pretty_generate(data)}\n")
    end

    def reconciliation_data
      JSON.parse(File.read(@files.reconciliation_path(@state.fetch('current_round'))))
    end

    def review_findings
      reconciliation_data.fetch('findings')
    end

    def pause_for_evidence_verification
      data = reconciliation_data
      manual = data.fetch('manual_verification_findings')
      all_findings = (data.fetch('findings') + manual).uniq { |finding| finding['id'] }
      path = @files.manual_verification_path(@state.fetch('current_round'))
      payload = { 'findings' => all_findings, 'manual_verification_ids' => manual.map { |finding| finding['id'] } }
      File.write(path, "#{JSON.pretty_generate(payload)}\n")
      pause_for_user(evidence_verification_question(path))
    end

    def manual_verification_payload
      JSON.parse(File.read(@files.manual_verification_path(@state.fetch('current_round'))))
    end

    def resolution_data
      JSON.parse(File.read(@files.resolutions_path(@state.fetch('current_round'))))
    end

    def write_resolutions(data)
      File.write(@files.resolutions_path(@state.fetch('current_round')), "#{JSON.pretty_generate(data)}\n")
    end

    def evidence_verification_question(path)
      "Addressit requires operator verification before fixing review findings. Read #{path}, classify every finding " \
        "as accept or skip, then run: addressit resolve #{@context.task_folder} <resolution-json>"
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
      path = @files.manager_hypotheses_path(@state.fetch('current_round'))
      hypotheses = JSON.parse(File.read(path))['hypotheses']
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
      commands = File.file?(File.join(@context.repo_root, 'Gemfile')) ? ['bundle exec rubocop', 'bundle exec rspec'] : []
      results = commands.map { |command| execute_check(command) }
      File.write(@files.final_checks_path, format_checks(results))
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
      deadline = Time.now + WORKER_STATUS_TIMEOUT_SECONDS
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
      stage_name = stage_name.sub('REVIEWER', review_agent.upcase)
      context = ["Round #{@state.fetch('current_round')}"]
      context << "Iteration #{iteration}" if iteration

      puts
      puts '=================='
      puts "[#{stage_name} — #{context.join(' — ')}]"
      puts '=================='
    end

    def review_agent
      @state.fetch('review_agent')
    end

    def read_status(agent, phase, iteration = nil)
      path = @files.status_path(@state.fetch('current_round'), agent, phase, iteration)
      validator = Autowork::StatusValidator.new
      result = validator.validate_file(path, expected: { 'agent' => agent, 'phase' => phase, 'step' => 0 })
      raise Error, "Invalid worker status #{path}: #{result.errors.join('; ')}" unless result.valid?

      result.data
    end

    def send_prompt(path, role: :worker)
      roles = @tmux.discover_roles(@context.repo_root)
      target = role == :reviewer ? roles.reviewer.id : roles.worker.id
      @tmux.send_prompt(target, path)
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
      puts "Addressit round #{round}: agent-manager must write current-only review hypotheses."
      puts "Do not read historical risk data yet. Write JSON with a hypotheses array to: #{@files.manager_hypotheses_path(round)}"
      puts '{"hypotheses":[{"id":"H1","kind":"...","check":"...","reason":"..."}]}'
      puts "Then run: addressit audit-start #{@context.task_folder} #{@files.manager_hypotheses_path(round)}"
    end

    def print_risk_reconciliation_gate
      round = @state.fetch('current_round')
      registry = File.join(Autowork::TASK_ROOT, @context.project, 'review-risk-registry.json')
      puts "Addressit round #{round}: agent-manager must reconcile blind audits."
      puts "Now read the project risk registry: #{registry}"
      puts "Prioritize active, high-weight risks only when their tags/triggers match this diff."
      puts "Write the final manifest to: #{@files.risk_manifest_path(round)}"
      puts '{"summary":"...","coverage_gaps":[],"hypothesis_coverage":[{"id":"H1","status":"covered","note":"..."}],"additional_findings":[{"id":"R1","severity":"BLOCKER","title":"...","body":"...","verification":"actionable|needs_context","trigger":"...","mechanism":"...","reachability_source":"normal_execution_path","evidence":"...","missing_evidence":"required when verification is needs_context"}],"registry_updates":[]}'
      puts "Acknowledge every hypothesis exactly once in hypothesis_coverage with status covered and a short note. Resolve every gap; use coverage_gaps: [] only when none remain. Additional findings need the same evidence fields as audit findings; use needs_context when reachability is unproven."
      puts "Then run: addressit audit-reconcile #{@context.task_folder} #{@files.risk_manifest_path(round)}"
    end

    def print_manager_gate
      puts "Addressit is ready for agent-manager review."
      puts "Review diff, comments, audits, risk manifest, checks, and commits; write #{@files.manager_review_path}."
      puts "Then run: addressit manager-pass #{@context.task_folder}"
    end

    def ensure_clean_before_commit!
      expected_head = @state['baseline_head']
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
      @review_agent = extract_review_agent!
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

    def extract_review_agent!
      indexes = @argv.each_index.select { |index| @argv[index] == '--agent' }
      raise Error, 'Pass --agent only once' if indexes.length > 1
      return if indexes.empty?

      index = indexes.first
      agent = @argv[index + 1]
      unless REVIEW_AGENTS.include?(agent)
        raise Error, "--agent must be one of: #{REVIEW_AGENTS.join(', ')}"
      end

      @argv.slice!(index, 2)
      agent
    end

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

    def start_or_resume
      context = resolve_context
      files = Files.new(context.task_folder)
      is_new_run = !File.file?(files.state_path)
      Autowork::TaskRepoSnapshot.commit!(context.task_folder) if is_new_run
      files.mkdirs
      state = load_or_initialize_state(files)
      normalize_state!(state)
      source = review_source
      if source.respond_to?(:repo)
        context.pr_repo = source.repo
        context.pr_number = source.number
      end
      Store.new(files.state_path).write(state)
      lock = Lock.new(files.lock_path)
      lock.acquire!
      begin
        if %w[complete no_new_comments round_skipped].include?(state['phase'])
          state['phase'] = 'ready_to_fetch'
          Store.new(files.state_path).write(state)
          Orchestrator.new(context, files, state).prepare_round!(source)
        elsif state['phase'] == 'ready_to_fetch'
          Orchestrator.new(context, files, state).prepare_round!(source)
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
      normalize_state!(state)
      Store.new(files.state_path).write(state)
      repo_root = File.realpath(Autowork::Shell.capture!('git', '-C', @cwd, 'rev-parse', '--show-toplevel').strip)
      repo, number = artifact_review_target(files, state)
      context = Context.new(
        project: File.basename(File.dirname(task_folder)),
        task_id: File.basename(task_folder)[/\A\d+/],
        task_folder: task_folder,
        repo_root: repo_root,
        branch: Autowork::Shell.capture!('git', '-C', repo_root, 'branch', '--show-current').strip,
        pr_repo: repo,
        pr_number: number
      )
      [context, files, state]
    end

    def load_or_initialize_state(files)
      return Store.new(files.state_path).read if File.file?(files.state_path)

      initial_state
    end

    def artifact_review_target(files, state)
      round = state['current_round']
      return [nil, nil] unless round && File.file?(files.comments_path(round))

      comments = JSON.parse(File.read(files.comments_path(round)))
      url = comments.filter_map { |comment| comment['html_url'] }.first
      match = url&.match(%r{github\.com/([^/]+/[^/]+)/pull/(\d+)})
      match ? [match[1], match[2]] : [nil, nil]
    end

    def normalize_state!(state)
      migrate_legacy_reviewer_state!(state)
      migrate_comment_ids!(state)
      current_agent = state['review_agent'] || 'claude'
      validate_review_agent_change!(state, current_agent)
      state['review_agent'] = @review_agent || current_agent
    end

    def migrate_legacy_reviewer_state!(state)
      state['phase'] = LEGACY_REVIEW_PHASES.fetch(state['phase'], state['phase'])
    end

    def migrate_comment_ids!(state)
      ledger = Array(state.delete('comment_ledger'))
      %w[addressed skipped].each do |disposition|
        key = "#{disposition}_ids"
        legacy_ids = ledger.filter_map { |entry| entry['id'].to_s if entry['state'] == disposition }
        state[key] = (Array(state[key]) + legacy_ids).uniq
      end
      migrate_current_round!(state, Array(state.delete('rounds')))
      state.delete('commits')
      %w[
        version project task_id task_folder repo_root branch_name pr_repo pr_number
        final_check_commands worker_status_timeout_minutes max_fix_iterations max_total_commits
        created_at updated_at github_comments_fetched_at
      ].concat(OBSOLETE_STATE_KEYS).each { |key| state.delete(key) }
      clear_finished_state!(state)
    end

    def migrate_current_round!(state, rounds)
      round = rounds.find { |entry| entry['number'] == state['current_round'] }
      return unless round

      %w[baseline_head round_start_head commit_shas].each do |key|
        state[key] ||= round[key]
      end
    end

    def clear_finished_state!(state)
      return unless %w[complete no_new_comments round_skipped].include?(state['phase'])

      CURRENT_ROUND_STATE_KEYS.each { |key| state.delete(key) }
    end

    def validate_review_agent_change!(state, current_agent)
      return unless @review_agent && @review_agent != current_agent
      return if REVIEW_AGENT_CHANGE_PHASES.include?(state['phase'])

      raise Error, "Cannot change reviewer from #{current_agent} to #{@review_agent} while phase is #{state['phase']}"
    end

    def initial_state
      {
        'review_agent' => @review_agent || DEFAULT_REVIEW_AGENT,
        'phase' => 'ready_to_fetch',
        'addressed_ids' => [],
        'skipped_ids' => []
      }
    end
  end
end
