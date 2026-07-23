# frozen_string_literal: true

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
    def initialize(cwd: Dir.pwd, shell: Autowork::Shell)
      @cwd = File.expand_path(cwd)
      @shell = shell
    end

    def resolve
      repo_root = File.realpath(@shell.capture!('git', '-C', @cwd, 'rev-parse', '--show-toplevel').strip)
      project = infer_project(repo_root)
      task_root = File.join(TASK_ROOT, project)
      raise Error, "Task project not found: #{task_root}" unless File.directory?(task_root)

      branch = @shell.capture!('git', '-C', repo_root, 'branch', '--show-current').strip
      task_id = infer_task_id(branch)
      raise Error, "No task folder found for branch #{branch.inspect}." unless task_id

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

      mappings = {
        %r{\A/Volumes/dev/projects/shaka/gtm/(?:1st|2nd|3rd)(?:/|\z)} => 'shaka_gtm',
        %r{\A/Volumes/dev/projects/mydev/([^/]+)(?:/|\z)} => ->(match) { match[1] },
        %r{\A/Volumes/dev/projects/shaka/([^/]+)(?:/|\z)} => ->(match) { match[1] },
        %r{\A/Volumes/dev/projects/misc/([^/]+)(?:/|\z)} => ->(match) { match[1] }
      }
      mappings.each do |pattern, value|
        match = path.match(pattern)
        next unless match

        project = value.respond_to?(:call) ? value.call(match) : value
        raise Error, "Cannot infer project from #{path.inspect}." unless project == 'shaka_gtm' || project.match?(/\A(?:my_|shaka_|misc_)/)

        return project
      end
      raise Error, "Could not infer project from #{path.inspect}. Pass a checkout in a known project."
    end

    def infer_task_id(branch)
      match = branch.match(%r{(?:^|/)sc-(\d+)(?:/|$)})
      return match[1] if match

      match = branch.match(%r{(?:^|/)(\d{4})(?:-|/|$)})
      match && match[1]
    end
  end

  class Files
    attr_reader :task_folder, :log_dir

    def initialize(task_folder)
      @task_folder = task_folder
      @log_dir = File.join(task_folder, 'addressit-log')
    end

    def mkdirs
      %w[prompts reviews debates status rounds].each { |name| FileUtils.mkdir_p(File.join(log_dir, name)) }
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

  class GitHub
    attr_reader :repo, :number

    def initialize(argv, shell: Autowork::Shell)
      @argv = argv.dup
      @shell = shell
      @repo, @number, @specific_comment, @specific_review = parse_target
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
      @argv.join(' ').match?(/\ball\s+comments\b/i)
    end

    private

    def parse_target
      target = @argv.shift
      raise Error, 'Usage: addressit <pr-number-or-github-url> [filters]' unless target

      if target.match?(%r{\Ahttps?://github\.com/[^/]+/[^/]+/pull/\d+})
        match = target.match(%r{github\.com/([^/]+)/([^/]+)/pull/(\d+)(?:#(.*))?})
        fragment = match[4].to_s
        specific_comment = fragment[/discussion_r(\d+)/, 1]
        specific_review = fragment[/pullrequestreview-(\d+)/, 1]
        return ["#{match[1]}/#{match[2]}", match[3], specific_comment, specific_review]
      end

      raise Error, "Invalid PR target: #{target.inspect}" unless target.match?(/\A\d+\z/)

      repository = @shell.capture!('gh', 'repo', 'view', '--json', 'nameWithOwner', '-q', '.nameWithOwner').strip
      [repository, target, nil, nil]
    end

    def apply_filters(comments)
      text = @argv.join(' ')
      if (match = text.match(/(?:comments\s+)?from\s+@?([A-Za-z0-9_-]+)/i))
        comments = comments.select { |comment| comment.dig('user', 'login') == match[1] }
      end
      return comments unless (match = text.match(/since\s+(.+)\z/i))

      threshold = parse_time(match[1])
      comments.select do |comment|
        [comment['created_at'], comment['updated_at']].compact.any? { |value| Time.parse(value) >= threshold }
      end
    end

    def parse_time(value)
      return Time.parse(value) if value.match?(/\d{4}-\d{2}-\d{2}T/)

      seconds = case value.strip.downcase
                when /^(\d+)\s+hours?\s+ago$/ then Regexp.last_match(1).to_i * 3600
                when /^yesterday$/ then 86_400
                else raise Error, "Could not parse since filter #{value.inspect}"
                end
      Time.now - seconds
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

        Review every approved comment and inspect for regressions introduced by the commit. Do not edit files and do not run tests, linters, or formatters. Use read-only inspection and Pi's reported checks.
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
    def initialize(context, files, state, tmux: Autowork::Tmux.new, shell: Autowork::Shell)
      @context = context
      @files = files
      @state = state
      @tmux = tmux
      @shell = shell
      @repo = Autowork::GitRepo.new(context.repo_root)
    end

    def prepare_round!(github)
      raise Error, "Refusing to start with dirty worktree in #{@context.repo_root}:\n#{@repo.status}" unless @repo.clean?

      comments = github.comments
      candidates = comments.reject { |comment| Ledger.new(@state).addressed_or_skipped?(comment) }
      @state['github_comments_fetched_at'] = Time.now.iso8601
      @state['current_round'] = (@state['rounds'].map { |round| round['number'] }.max || 0) + 1
      round = @state['current_round']
      File.write(@files.comments_path(round), JSON.pretty_generate(candidates) + "\n")
      @state['rounds'] << { 'number' => round, 'selected_ids' => candidates.map { |comment| comment['id'].to_s }, 'baseline_head' => @repo.head_sha, 'status' => 'awaiting_approval' }
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
      round_state.merge!('approved_ids' => approved, 'skipped_ids' => skipped, 'status' => approved.empty? ? 'skipped' : 'approved')
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
      approved_ids = @state['rounds'].find { |entry| entry['number'] == round }.fetch('approved_ids')
      ledger = Ledger.new(@state)
      comments.select { |comment| approved_ids.include?(comment['id'].to_s) }.each do |comment|
        ledger.save(comment, state: 'addressed')
      end
      @state['rounds'].find { |entry| entry['number'] == round }['status'] = 'addressed'
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

    def commit_implementation
      ensure_clean_before_commit!
      raise Error, 'Pi-worker reported completion but produced no repository changes' if @repo.clean?

      @repo.add_all
      commit_sha = @repo.commit("Address PR ##{@context.pr_number} round #{@state.fetch('current_round')}")
      @state['commits'] << commit_sha
      @state['review_iteration'] = 1
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
      elsif Array(status['findings']).empty?
        @state['phase'] = 'ready_for_final_checks'
        save_state
      else
        @state['claude_findings'] = status['findings']
        @state['phase'] = 'ready_to_send_classify'
        save_state
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
      unless disputes.empty?
        @state['accepted_resolutions'] = accepted
        @state['debate_findings'] = @state.fetch('claude_findings').select { |finding| disputes.any? { |item| item['finding_id'] == finding['id'] } }
        @state['debate_resolutions'] = disputes
        @state['debate_round'] = 1
        @state['phase'] = 'ready_to_send_claude_debate'
        save_state
        return
      end
      accepted = resolutions.select { |resolution| %w[accept accept_with_alternative_fix].include?(resolution['decision']) }
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
      sha = @repo.commit("Address PR ##{@context.pr_number} round #{@state.fetch('current_round')} manager fix #{@state.fetch('manager_fix_iteration')}")
      @state['commits'] << sha
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
      commit_sha = @repo.commit("Address PR ##{@context.pr_number} round #{@state.fetch('current_round')} fix #{@state.fetch('fix_iteration')}")
      @state['commits'] << commit_sha
      @state['review_iteration'] += 1
      send_claude
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
      puts "Addressit round #{round}: #{comments.length} new inline review comment(s)."
      comments.each_with_index do |comment, index|
        location = comment['path'].to_s
        location += ":#{comment['line']}" if comment['line']
        puts "#{index + 1}. @#{comment.dig('user', 'login')} #{location} comment=#{comment['id']} #{comment['html_url']}"
      end
      puts "Full comments: #{@files.comments_path(round)}"
      puts "Write approval JSON to #{@files.approval_path(round)} and run: addressit approve #{@context.task_folder} <approval-json>"
    end

    def print_manager_gate
      puts "Addressit is ready for pi-manager review."
      puts "Review diff, comments, checks, and commits; write #{@files.manager_review_path}."
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
    end

    def run
      command = @argv.first
      case command
      when 'approve'
        approve
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

    def resolve_context
      TaskResolver.new(cwd: @cwd).resolve
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
      files.mkdirs
      state = if File.file?(files.state_path)
                Store.new(files.state_path).read
              else
                github = GitHub.new(@argv)
                repo, number = github.repo, github.number
                final_commands = File.file?(File.join(context.repo_root, 'Gemfile')) ? ['bundle exec rubocop', 'bundle exec rspec'] : []
                initial_state(context, repo, number, final_commands)
              end
      write_config(files, state) unless File.file?(files.config_path)
      if state['pr_repo']
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
          github = GitHub.new(@argv)
          state['phase'] = 'ready_to_fetch'
          Store.new(files.state_path).write(state)
          Orchestrator.new(context, files, state).prepare_round!(github)
        elsif state['phase'] == 'ready_to_fetch'
          Orchestrator.new(context, files, state).prepare_round!(GitHub.new(@argv))
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
        'pr_number' => number.to_i,
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
