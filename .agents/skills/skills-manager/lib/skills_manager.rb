# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'open3'
require 'optparse'
require 'pathname'
require 'shellwords'
require 'time'
require 'yaml'

module SkillsManager
  Error = Class.new(StandardError)

  REPO_ROOT = Pathname.new(__dir__).join('..', '..', '..', '..').expand_path
  DEFAULT_EXTERNAL_ROOT = REPO_ROOT.join('.ai', 'external-skills')
  DEFAULT_MANIFEST_PATH = DEFAULT_EXTERNAL_ROOT.join('external-skills.yml')
  REQUIRED_AUDITOR_NAMES = %w[skillspector cisco-skill-scanner sentry-skill-scanner].freeze
  BLOCKING_STATUSES = %w[fail error].freeze
  WARNING_STATUSES = %w[warn].freeze
  SEVERITY_RANK = {
    'none' => 0,
    'clean' => 0,
    'info' => 1,
    'informational' => 1,
    'low' => 2,
    'medium' => 3,
    'moderate' => 3,
    'caution' => 3,
    'high' => 4,
    'critical' => 5,
    'do_not_install' => 5,
    'do not install' => 5
  }.freeze

  CommandOutput = Struct.new(:stdout, :stderr, :exit_status, keyword_init: true)
  AuditResult = Struct.new(:auditor, :status, :severity, :summary, :report_path, keyword_init: true)

  class Manager
    attr_reader :repo_root, :external_root, :manifest_path, :dry_run, :allow_warnings

    def initialize(repo_root: REPO_ROOT, external_root: DEFAULT_EXTERNAL_ROOT, manifest_path: nil, dry_run: false, allow_warnings: false)
      @repo_root = Pathname.new(repo_root).expand_path
      @external_root = Pathname.new(external_root).expand_path
      @manifest_path = Pathname.new(manifest_path || @external_root.join('external-skills.yml')).expand_path
      @dry_run = dry_run
      @allow_warnings = allow_warnings
    end

    def list(name = nil)
      selected_skills(name).each do |skill_name, skill|
        puts skill_name
        puts "  origin:   #{skill.fetch('origin')}"
        puts "  ref:      #{skill.fetch('ref', 'HEAD')}"
        puts "  checkout: #{checkout_path(skill)}"
        puts "  target:   #{target_path(skill)}"
        puts "  auditor:  #{skill['auditor'] ? 'yes' : 'no'}"
        puts "  adapter:  #{skill['adapter'] || '(none)'}" if skill['auditor']
      end
    end

    def status(name = nil)
      selected_skills(name).each do |skill_name, skill|
        path = checkout_path(skill)
        puts skill_name
        puts "  checkout: #{path}"
        puts "  target:   #{target_path(skill)}"
        if path.join('.git').directory?
          puts "  git:      #{git_branch(path)} @ #{git_head(path, short: true)}"
          puts "  remote:   #{capture_or_empty('git', '-C', path.to_s, 'remote', 'get-url', 'origin').strip}"
          puts "  dirty:    #{checkout_dirty?(path) ? 'yes' : 'no'}"
        elsif skill['source_path'] && target_path(skill).directory?
          synced = state.fetch('synced', {})[skill_name]
          puts "  git:      exported @ #{synced ? synced.fetch('head', '(unknown)') : '(unknown)'}"
          puts '  dirty:    n/a'
        else
          puts '  git:      missing checkout'
        end
        install = state.fetch('installed', {})[skill_name]
        puts "  installed: #{install ? install.fetch('head', '(unknown)') : 'no'}"
      end
    end

    def sync(name = nil)
      FileUtils.mkdir_p(external_root) unless dry_run
      selected_skills(name).each do |skill_name, skill|
        puts "==> #{skill_name}"
        sync_skill(skill)
      end
    end

    def audit_plan(name)
      skill = fetch_skill(name)
      audit_names_for(name, skill)
    end

    def audit(name)
      skill = fetch_skill(name)
      raise Error, "#{name} is an auditor; auditor skills are not audited by skills-manager" if skill['auditor']

      ensure_checkout_ready!(name, skill)
      ensure_auditors_ready!(name, skill)

      bundle = create_audit_bundle(name, skill)
      results = audit_plan(name).map do |auditor_name|
        run_auditor(auditor_name, target_path(skill), bundle)
      end
      write_audit_summary(name, skill, bundle, results)
      print_audit_summary(bundle, results)
      ensure_audit_passed!(results)
      bundle
    end

    def install(name)
      skill = fetch_skill(name)
      ensure_checkout_ready!(name, skill)
      audit_bundle = if skill['auditor']
                       nil
                     elsif dry_run
                       puts "  would audit #{name}"
                       'fresh audit'
                     else
                       audit(name)
                     end
      apply_install_actions(name, skill, audit_bundle)
      record_install(name, skill, audit_bundle)
      verb = dry_run ? 'Would install' : 'Installed'
      puts(audit_bundle ? "#{verb} #{name} after fresh audit: #{audit_bundle}" : "#{verb} #{name}")
    end

    def update(name = nil)
      selected_skills(name).each_key do |skill_name|
        sync(skill_name)
        install(skill_name)
      end
    end

    private

    def manifest
      @manifest ||= begin
        raise Error, "missing external skills manifest: #{manifest_path}" unless manifest_path.file?

        data = YAML.safe_load(manifest_path.read, permitted_classes: [], aliases: false)
        normalize_manifest(data)
      end
    end

    def selected_skills(name)
      return manifest.to_h { |skill_name, skill| [skill_name, skill.merge('_name' => skill_name)] } if name.nil?

      { name => fetch_skill(name) }
    end

    def fetch_skill(name)
      skill = manifest.fetch(name) { raise Error, "unknown external skill: #{name}" }
      skill.merge('_name' => name)
    end

    def auditors
      manifest.select { |_name, skill| skill['auditor'] }
    end

    def normalize_manifest(data)
      auditors = data.fetch('auditors', {}).transform_values { |skill| skill.merge('auditor' => true) }
      skills = data.fetch('skills', {}) || {}
      auditors.merge(skills)
    end

    def audit_names_for(name, skill)
      missing = REQUIRED_AUDITOR_NAMES - auditors.keys
      raise Error, "manifest is missing required auditor skill(s): #{missing.join(', ')}" unless missing.empty?

      return [] if skill['auditor']

      REQUIRED_AUDITOR_NAMES.dup
    end

    def checkout_path(skill)
      managed_path(skill.fetch('checkout') { default_checkout(skill) }, 'checkout')
    end

    def target_path(skill)
      if skill['target'] || skill['source_path']
        managed_path(skill.fetch('target') { skill.fetch('_name') }, 'target')
      else
        checkout = checkout_path(skill)
        path = checkout.join(skill.fetch('skill_path', '.')).expand_path
        unless inside_path?(path, checkout)
          raise Error, "skill_path must stay inside checkout #{checkout}: #{path}"
        end
        path
      end
    end

    def default_checkout(skill)
      skill.fetch('_name')
    end

    def managed_path(relative_path, label)
      raise Error, "#{label} path must be relative: #{relative_path}" if Pathname.new(relative_path).absolute?

      path = external_root.join(relative_path).expand_path
      unless inside_path?(path, external_root)
        raise Error, "#{label} path must stay under #{external_root}: #{path}"
      end
      path
    end

    def inside_path?(path, root)
      path.to_s == root.to_s || path.to_s.start_with?(root.to_s + File::SEPARATOR)
    end

    def ensure_checkout_ready!(name, skill)
      path = checkout_path(skill)
      if skill['source_path']
        raise Error, "#{name} export is missing; run skills-manager sync #{name}" unless target_path(skill).directory?
        return
      end

      raise Error, "#{name} checkout is missing; run skills-manager sync #{name}" unless path.join('.git').directory?
      raise Error, "#{name} checkout has local changes; refusing to audit mutable content" if checkout_dirty?(path)
      raise Error, "#{target_path(skill)} does not exist" unless target_path(skill).exist?
    end

    def ensure_auditors_ready!(target_name, target_skill)
      audit_names_for(target_name, target_skill).each do |auditor_name|
        auditor = fetch_skill(auditor_name)
        ensure_checkout_ready!(auditor_name, auditor)
      end
    end

    def sync_skill(skill)
      return sync_exported_skill(skill) if skill['source_path']

      path = checkout_path(skill)
      origin = skill.fetch('origin')
      ref = skill.fetch('ref', 'HEAD')

      if !path.join('.git').directory?
        FileUtils.mkdir_p(path.dirname) unless dry_run
        run('git', 'clone', '--branch', ref, origin, path.to_s)
        return
      end

      remote = capture('git', '-C', path.to_s, 'remote', 'get-url', 'origin').stdout.strip
      raise Error, "#{path} origin is #{remote.inspect}, expected #{origin.inspect}" unless remote == origin
      raise Error, "#{path} has local changes; commit/remove them before updating" if checkout_dirty?(path)

      run('git', '-C', path.to_s, 'fetch', '--prune', 'origin', ref)
      run('git', '-C', path.to_s, 'merge', '--ff-only', 'FETCH_HEAD')
    end

    def sync_exported_skill(skill)
      temp = external_root.join('.tmp', skill.fetch('_name')).expand_path
      source = temp.join(skill.fetch('source_path')).expand_path
      target = target_path(skill)

      if dry_run
        puts "  would clone temp: #{skill.fetch('origin')} -> #{temp}"
        puts "  would export: #{source} -> #{target}"
        puts "  would remove temp: #{temp}"
        return
      end

      FileUtils.rm_rf(temp)
      FileUtils.mkdir_p(temp.dirname)
      begin
        run('git', 'clone', '--depth', '1', '--branch', skill.fetch('ref', 'HEAD'), skill.fetch('origin'), temp.to_s)
        raise Error, "source_path does not exist: #{source}" unless source.exist?

        FileUtils.rm_rf(target)
        FileUtils.mkdir_p(target.dirname)
        FileUtils.cp_r(source, target)
        record_sync(skill, git_head(temp, short: false))
      ensure
        FileUtils.rm_rf(temp)
        temp.dirname.rmdir if temp.dirname.directory? && temp.dirname.children.empty?
      end
    end

    def create_audit_bundle(name, skill)
      head = current_head(skill, short: true)
      timestamp = Time.now.utc.strftime('%Y%m%dT%H%M%SZ')
      path = external_root.join('audits', name, "#{timestamp}-#{head}")
      FileUtils.mkdir_p(path) unless dry_run
      path
    end

    def run_auditor(auditor_name, scan_target, bundle)
      auditor = fetch_skill(auditor_name)
      auditor_dir = checkout_path(auditor)
      case auditor.fetch('adapter')
      when 'skillspector'
        run_skillspector(auditor_name, auditor_dir, scan_target, bundle)
      when 'cisco_skill_scanner'
        run_cisco_skill_scanner(auditor_name, auditor_dir, scan_target, bundle)
      when 'sentry_skill_scanner'
        run_sentry_skill_scanner(auditor_name, target_path(auditor), scan_target, bundle)
      else
        raise Error, "#{auditor_name} has unknown adapter: #{auditor['adapter'].inspect}"
      end
    end

    def run_skillspector(auditor_name, auditor_dir, scan_target, bundle)
      report = bundle.join("#{auditor_name}.json")
      command = ['uv', 'run', '--directory', auditor_dir.to_s, 'skillspector', 'scan', scan_target.to_s, '--no-llm', '--format', 'json', '--output', report.to_s]
      output = capture_audit_command(auditor_name, command, bundle)
      parsed = read_json_report(report)
      normalized_result(auditor_name, parsed, output, report, 'SkillSpector')
    end

    def run_cisco_skill_scanner(auditor_name, auditor_dir, scan_target, bundle)
      report = bundle.join("#{auditor_name}.json")
      command = ['uv', 'run', '--directory', auditor_dir.to_s, 'skill-scanner', 'scan', scan_target.to_s, '--lenient', '--use-behavioral', '--policy', 'strict', '--format', 'json', '--output', report.to_s, '--fail-on-severity', 'high']
      output = capture_audit_command(auditor_name, command, bundle)
      parsed = read_json_report(report)
      normalized_result(auditor_name, parsed, output, report, 'Cisco skill-scanner')
    end

    def run_sentry_skill_scanner(auditor_name, auditor_skill_dir, scan_target, bundle)
      report = bundle.join("#{auditor_name}.json")
      command = ['uv', 'run', 'scripts/scan_skill.py', scan_target.to_s]
      output = capture_audit_command(auditor_name, command, bundle, chdir: auditor_skill_dir)
      write_file(report, output.stdout)
      parsed = parse_json(output.stdout)
      normalized_result(auditor_name, parsed, output, report, 'Sentry skill-scanner')
    end

    def capture_audit_command(auditor_name, command, bundle, chdir: nil)
      command_path = bundle.join("#{auditor_name}.command.txt")
      stdout_path = bundle.join("#{auditor_name}.stdout.txt")
      stderr_path = bundle.join("#{auditor_name}.stderr.txt")
      write_file(command_path, command.shelljoin)

      output = capture(*command, chdir: chdir, allow_failure: true)
      write_file(stdout_path, output.stdout)
      write_file(stderr_path, output.stderr)
      output
    end

    def normalized_result(auditor_name, parsed, output, report, label)
      if parsed.nil?
        return AuditResult.new(
          auditor: auditor_name,
          status: 'error',
          severity: 'unknown',
          summary: "#{label} did not produce parseable JSON (exit #{output.exit_status})",
          report_path: report.to_s
        )
      end

      severity = max_severity(parsed)
      recommendation = recommendation(parsed)
      status = normalized_status(severity, recommendation, output.exit_status)
      AuditResult.new(
        auditor: auditor_name,
        status: status,
        severity: severity,
        summary: result_summary(label, severity, recommendation, output.exit_status),
        report_path: report.to_s
      )
    end

    def normalized_status(severity, recommendation, exit_status)
      rank = SEVERITY_RANK.fetch(severity.to_s.downcase, 0)
      return 'fail' if recommendation == 'DO_NOT_INSTALL'
      return 'fail' if rank >= SEVERITY_RANK.fetch('high')
      return 'warn' if rank == SEVERITY_RANK.fetch('medium')
      return 'error' if exit_status == 2
      return 'error' if exit_status != 0 && rank < SEVERITY_RANK.fetch('high')

      'pass'
    end

    def result_summary(label, severity, recommendation, exit_status)
      parts = ["#{label}: severity=#{severity}"]
      parts << "recommendation=#{recommendation}" if recommendation
      parts << "exit=#{exit_status}"
      parts.join(', ')
    end

    def max_severity(obj)
      rank, value = severity_candidates(obj).max_by { |candidate| candidate.first } || [0, 'none']
      rank.zero? ? 'none' : value
    end

    def severity_candidates(obj)
      case obj
      when Hash
        direct = obj.flat_map do |key, value|
          candidates = []
          key_text = key.to_s.downcase
          if value.is_a?(Numeric) && value.positive? && SEVERITY_RANK.key?(key_text)
            candidates << [SEVERITY_RANK.fetch(key_text), key_text]
          elsif key_text.include?('severity') || key_text.include?('risk')
            severity = normalize_severity(value)
            candidates << [SEVERITY_RANK.fetch(severity), severity] if severity
          end
          candidates + severity_candidates(value)
        end
        direct
      when Array
        obj.flat_map { |value| severity_candidates(value) }
      else
        []
      end
    end

    def normalize_severity(value)
      return nil unless value.is_a?(String)

      normalized = value.strip.downcase.tr('-', '_')
      return normalized if SEVERITY_RANK.key?(normalized)

      spaced = normalized.tr('_', ' ')
      return spaced if SEVERITY_RANK.key?(spaced)

      nil
    end

    def recommendation(obj)
      case obj
      when Hash
        obj.each do |key, value|
          if key.to_s.downcase.include?('recommendation') && value.is_a?(String)
            normalized = value.strip.upcase.tr(' ', '_').tr('-', '_')
            return normalized
          end
          nested = recommendation(value)
          return nested if nested
        end
      when Array
        obj.each do |value|
          nested = recommendation(value)
          return nested if nested
        end
      end
      nil
    end

    def write_audit_summary(name, skill, bundle, results)
      summary_yml = {
        'skill' => name,
        'target' => target_path(skill).to_s,
        'head' => git_head(checkout_path(skill), short: false),
        'audited_at' => Time.now.utc.iso8601,
        'policy' => policy_text(skill['auditor']),
        'results' => results.map { |result| result.to_h.transform_keys(&:to_s) },
        'decision' => audit_decision(results)
      }
      write_file(bundle.join('summary.yml'), YAML.dump(summary_yml))
      write_file(bundle.join('summary.md'), audit_summary_markdown(summary_yml))
    end

    def audit_summary_markdown(summary)
      lines = []
      lines << "# Skills-manager audit: #{summary.fetch('skill')}"
      lines << ''
      lines << "- Target: `#{summary.fetch('target')}`"
      lines << "- HEAD: `#{summary.fetch('head')}`"
      lines << "- Audited at: #{summary.fetch('audited_at')}"
      lines << "- Policy: #{summary.fetch('policy')}"
      lines << "- Decision: **#{summary.fetch('decision')}**"
      lines << ''
      lines << '| Auditor | Status | Severity | Summary |'
      lines << '| --- | --- | --- | --- |'
      summary.fetch('results').each do |result|
        lines << "| #{result.fetch('auditor')} | #{result.fetch('status')} | #{result.fetch('severity')} | #{result.fetch('summary').to_s.gsub('|', '\\|')} |"
      end
      lines << ''
      lines << 'Raw reports live next to this file.'
      lines << ''
      lines.join("\n")
    end

    def print_audit_summary(bundle, results)
      puts "Audit bundle: #{bundle}"
      results.each do |result|
        puts "  #{result.auditor}: #{result.status} (#{result.severity}) - #{result.summary}"
      end
      puts "Decision: #{audit_decision(results)}"
    end

    def audit_decision(results)
      return 'blocked' if results.any? { |result| BLOCKING_STATUSES.include?(result.status) }
      return allow_warnings ? 'allowed_with_warnings' : 'blocked_on_warnings' if results.any? { |result| WARNING_STATUSES.include?(result.status) }

      'passed'
    end

    def ensure_audit_passed!(results)
      blocked = results.select { |result| BLOCKING_STATUSES.include?(result.status) }
      raise Error, "audit blocked by #{blocked.map(&:auditor).join(', ')}" unless blocked.empty?

      warnings = results.select { |result| WARNING_STATUSES.include?(result.status) }
      return if warnings.empty? || allow_warnings

      raise Error, "audit has warnings from #{warnings.map(&:auditor).join(', ')}; rerun with --allow-warnings only after explicit user approval"
    end

    def apply_install_actions(name, skill, audit_bundle)
      actions = install_actions(skill)
      if actions.empty?
        puts "No install actions configured for #{name}; recorded audit/install receipt only."
        return
      end

      actions.each { |action| apply_install_action(name, skill, action, audit_bundle) }
    end

    def install_actions(skill)
      actions = Array(skill['install'])
      return actions unless actions.empty? && skill['auditor'] && skill['adapter'] == 'skillspector'

      [{ 'type' => 'pi_install' }]
    end

    def apply_install_action(name, skill, action, _audit_bundle)
      type = action.fetch('type')
      case type
      when 'copy_skill'
        copy_skill_action(name, skill, action)
      when 'pi_install'
        pi_install_action(name, skill)
      when 'claude_plugin'
        claude_plugin_action(name, skill)
      else
        raise Error, "unsupported install action for #{name}: #{type.inspect}"
      end
    end

    def pi_install_action(_name, skill)
      source = target_path(skill)
      puts "  pi install #{source}"
      return if dry_run

      run('pi', 'install', source.to_s)
    end

    def claude_plugin_action(name, skill)
      source = target_path(skill)
      puts "  claude plugin marketplace add #{source}"
      puts "  claude plugin install #{name}@#{name}"
      return if dry_run

      run('claude', 'plugin', 'marketplace', 'add', source.to_s)
      run('claude', 'plugin', 'install', "#{name}@#{name}")
    end

    def copy_skill_action(name, skill, action)
      source = target_path(skill).join(action.fetch('from', '.')).expand_path
      destination = repo_root.join(action.fetch('to')).expand_path
      unless destination.to_s.start_with?(repo_root.join('.ai', 'skills').to_s + File::SEPARATOR)
        raise Error, "copy_skill destination must be under .ai/skills: #{destination}"
      end
      raise Error, "copy_skill source does not exist: #{source}" unless source.exist?

      puts "  copy #{source} -> #{destination}"
      return if dry_run

      FileUtils.rm_rf(destination)
      FileUtils.mkdir_p(destination.dirname)
      FileUtils.cp_r(source, destination)
    end

    def record_install(name, skill, audit_bundle)
      return if dry_run

      data = state
      data['installed'] ||= {}
      data['installed'][name] = {
        'head' => current_head(skill, short: false),
        'target' => target_path(skill).to_s,
        'audit_bundle' => audit_bundle&.to_s,
        'installed_at' => Time.now.utc.iso8601,
        'allow_warnings' => allow_warnings
      }
      write_state(data)
    end

    def record_sync(skill, head)
      data = state
      data['synced'] ||= {}
      data['synced'][skill.fetch('_name')] = {
        'head' => head,
        'target' => target_path(skill).to_s,
        'synced_at' => Time.now.utc.iso8601
      }
      write_state(data)
    end

    def state
      @state ||= if state_path.file?
                   YAML.safe_load(state_path.read, permitted_classes: [], aliases: false) || {}
                 else
                   {}
                 end
    end

    def state_path
      external_root.join('state.yml')
    end

    def write_state(data)
      return if dry_run

      state_path.dirname.mkpath
      state_path.write(YAML.dump(data))
    end

    def policy_text(is_auditor)
      is_auditor ? 'auditor skill: audit skipped' : 'normal skill: audited by all three auditors'
    end

    def git_branch(path)
      branch = capture_or_empty('git', '-C', path.to_s, 'branch', '--show-current').strip
      branch.empty? ? '(detached)' : branch
    end

    def current_head(skill, short: false)
      if skill['source_path']
        head = state.fetch('synced', {}).fetch(skill.fetch('_name'), {}).fetch('head', nil)
        raise Error, "#{skill.fetch('_name')} sync state is missing; run skills-manager sync #{skill.fetch('_name')}" unless head

        short ? head[0, 7] : head
      else
        git_head(checkout_path(skill), short: short)
      end
    end

    def git_head(path, short: false)
      args = ['git', '-C', path.to_s, 'rev-parse']
      args << '--short' if short
      args << 'HEAD'
      capture(*args).stdout.strip
    end

    def checkout_dirty?(path)
      !capture_or_empty('git', '-C', path.to_s, 'status', '--porcelain').strip.empty?
    end

    def capture_or_empty(*cmd)
      capture(*cmd, allow_failure: true).stdout
    end

    def capture(*cmd, chdir: nil, allow_failure: false)
      return CommandOutput.new(stdout: '', stderr: '', exit_status: 0) if dry_run

      options = chdir ? { chdir: chdir.to_s } : {}
      stdout, stderr, status = Open3.capture3(*cmd.map(&:to_s), **options)
      unless status.success? || allow_failure
        raise Error, "#{cmd.shelljoin} failed: #{stderr.strip}"
      end
      CommandOutput.new(stdout: stdout, stderr: stderr, exit_status: status.exitstatus)
    end

    def run(*cmd)
      puts dry_run ? "  would run: #{cmd.shelljoin}" : "  run: #{cmd.shelljoin}"
      output = capture(*cmd, allow_failure: true)
      print output.stdout unless output.stdout.empty?
      warn output.stderr unless output.stderr.empty?
      raise Error, "#{cmd.shelljoin} failed" if output.exit_status != 0

      output
    end

    def read_json_report(path)
      return nil unless path.file?

      parse_json(path.read)
    end

    def parse_json(text)
      JSON.parse(text)
    rescue JSON::ParserError
      nil
    end

    def write_file(path, content)
      return if dry_run

      path.dirname.mkpath
      path.write(content.to_s)
    end
  end

  class CLI
    def self.run(argv)
      options = { dry_run: false, allow_warnings: false }
      parser = OptionParser.new do |opts|
        opts.banner = 'Usage: skills-manager [options] <list|status|sync|audit|install|update|audit-plan> [skill]'
        opts.on('-n', '--dry-run', 'Print planned mutating commands without applying changes') { options[:dry_run] = true }
        opts.on('--allow-warnings', 'Allow install/update when auditors return warnings; use only after explicit approval') { options[:allow_warnings] = true }
        opts.on('--manifest PATH', 'Path to external-skills.yml') { |value| options[:manifest_path] = value }
        opts.on('--external-root PATH', 'Path to external skills state root') { |value| options[:external_root] = value }
      end

      parser.parse!(argv)
      command = argv.shift || 'status'
      name = argv.shift
      manager = Manager.new(**options)

      case command
      when 'list'
        manager.list(name)
      when 'status'
        manager.status(name)
      when 'sync'
        manager.sync(name)
      when 'audit'
        require_name!(name, command)
        manager.audit(name)
      when 'install'
        require_name!(name, command)
        manager.install(name)
      when 'update'
        manager.update(name)
      when 'audit-plan'
        require_name!(name, command)
        puts manager.audit_plan(name).join("\n")
      else
        warn "unknown command: #{command}"
        warn parser
        return 2
      end
      0
    rescue Error, KeyError, Psych::SyntaxError => e
      warn "error: #{e.message}"
      1
    end

    def self.require_name!(name, command)
      raise Error, "#{command} requires a skill name" if name.nil? || name.empty?
    end
  end
end
