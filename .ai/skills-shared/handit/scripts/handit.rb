#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "tmpdir"

module Handit
  class Error < StandardError; end
  class UsageError < Error; end
  class SensitiveContentError < Error; end

  Task = Struct.new(:project, :folder, :path)

  TRANSIT_TEMPLATE = <<~MARKDOWN.freeze
    <!-- Paste the mobile discussion summary here. Any non-empty Markdown is accepted.
    Useful details can include decisions, reasoning, rejected alternatives, and VERIFY ON MAC items. -->
  MARKDOWN

  class Runner
    REQUIRED_FILES = %w[HANDOFF.md TRANSIT.md session.jsonl].freeze

    def initialize(tasks_root:, cloud_root:, scanner_path:, session_file:, session_id:, output: nil)
      @tasks_root = File.realpath(tasks_root)
      @cloud_root = File.expand_path(cloud_root)
      @scanner_path = File.expand_path(scanner_path)
      @session_file = session_file.to_s
      @session_id = session_id.to_s
      @output = output
    end

    def pass(task_path, summary_path, is_sensitive_allowed: false, is_summary_temporary: false)
      summary_path = File.expand_path(summary_path)
      staging_path = nil

      begin
        task = resolve_task(task_path)
        summary = read_summary(summary_path)
        validate_current_session!

        destination = handoff_path(task)
        raise Error, "Handoff already exists: #{destination}" if File.exist?(destination)

        FileUtils.mkdir_p(File.dirname(destination))
        staging_path = Dir.mktmpdir(".handoff-", File.dirname(destination))

        session_copy = File.join(staging_path, "session.jsonl")
        FileUtils.copy_file(@session_file, session_copy)
        validate_session_file!(session_copy)

        File.write(File.join(staging_path, "HANDOFF.md"), handoff_markdown(task, summary))
        File.write(File.join(staging_path, "TRANSIT.md"), TRANSIT_TEMPLATE)
        scan!(staging_path, is_sensitive_allowed: is_sensitive_allowed)

        File.rename(staging_path, destination)
        staging_path = nil
        destination
      ensure
        FileUtils.remove_entry(staging_path) if staging_path && File.exist?(staging_path)
        FileUtils.rm_f(summary_path) if is_summary_temporary
      end
    end

    def receive(task_path)
      task = resolve_task(task_path)
      destination = handoff_path(task)
      require_bundle!(destination)
      validate_current_session!
      validate_session_file!(File.join(destination, "session.jsonl"))

      transit_path = File.join(destination, "TRANSIT.md")
      transit = File.read(transit_path)
      meaningful_transit = transit.gsub(/<!--.*?-->/m, "").strip
      raise Error, "TRANSIT.md is empty: #{transit_path}" if meaningful_transit.empty?

      transit_path
    end

    def complete(task_path)
      task = resolve_task(task_path)
      destination = handoff_path(task)
      receive(task.path)
      FileUtils.remove_entry(destination)
      destination
    end

    private

    def resolve_task(task_path)
      canonical_path = File.realpath(task_path)
      expected_parent = @tasks_root
      project_path = File.dirname(canonical_path)
      raise Error, "Task must be directly below a registered task project: #{canonical_path}" unless File.dirname(project_path) == expected_parent

      project = File.basename(project_path)
      folder = File.basename(canonical_path)
      unless project.match?(/\A[a-z][a-z0-9_-]*\z/) && folder.match?(/\A(?:draft\d{2}|\d+-[a-z0-9][a-z0-9-]*)\z/)
        raise Error, "Invalid project or Task folder: #{canonical_path}"
      end
      raise Error, "Missing task.md: #{canonical_path}" unless File.file?(File.join(canonical_path, "task.md"))

      Task.new(project, folder, canonical_path)
    rescue Errno::ENOENT
      raise Error, "Task folder not found: #{task_path}"
    end

    def read_summary(summary_path)
      path = File.expand_path(summary_path)
      raise Error, "Summary file not found: #{path}" unless File.file?(path)

      File.read(path).strip
    end

    def validate_current_session!
      raise Error, "PI_SESSION_FILE is unavailable" if @session_file.empty?
      raise Error, "PI_SESSION_ID is unavailable" if @session_id.empty?
      raise Error, "Pi session file not found: #{@session_file}" unless File.file?(@session_file)

      validate_session_file!(@session_file)
    end

    def validate_session_file!(path)
      header = nil
      File.foreach(path).with_index do |line, index|
        entry = JSON.parse(line)
        header = entry if index.zero?
      rescue JSON::ParserError
        raise Error, "Invalid Pi session JSONL: #{path}"
      end

      unless header.is_a?(Hash) && header["type"] == "session" && header["id"] == @session_id
        raise Error, "Handoff does not belong to the original Pi session"
      end
    end

    def handoff_path(task)
      File.join(@cloud_root, task.project, task.folder, "handoff")
    end

    def handoff_markdown(task, summary)
      summary_section = summary.empty? ? "" : "\n## Current session context\n\n#{summary}\n"
      <<~MARKDOWN
        # Mobile Pi handoff

        Project: `#{task.project}`
        Task: `#{task.folder}`
        Pi session: `#{@session_id}`

        ## Mobile discussion rules

        The repository is unavailable during this discussion. Treat `session.jsonl` as the authoritative Pi history and this file only as a concise index. Distinguish established facts from assumptions, and mark repository-dependent claims as `VERIFY ON MAC`.

        Explain, challenge, compare, and refine the current reasoning. If asked to grill an idea, ask one grounded open question at a time. Do not claim to inspect unavailable files, change code, invoke local Pi workflows, or advance Grillme, Draftit, Taskit, Workit, Autoimplement, or Autofix state.
        #{summary_section}
        ## Return to Pi

        At the end, prepare a concise summary of the mobile discussion. The user will paste it into `TRANSIT.md`. Preserve decisions and their reasons, important rejected alternatives, changed assumptions, remaining questions, and anything marked `VERIFY ON MAC`. Any non-empty Markdown format is accepted.
      MARKDOWN
    end

    def scan!(staging_path, is_sensitive_allowed:)
      findings = []

      REQUIRED_FILES.each do |name|
        stdout, stderr, status = Open3.capture3(@scanner_path, "--file", File.join(staging_path, name))
        report = [stdout, stderr].reject(&:empty?).join("\n").strip

        if status.exitstatus == 1
          findings << report
          next
        end
        next if status.success?

        raise Error, "dots-check failed for #{name}: #{report}"
      end

      return if findings.empty?

      report = findings.join("\n\n")
      if is_sensitive_allowed
        @output&.puts(report)
        return
      end

      raise SensitiveContentError, "Sensitive content found; export blocked.\n#{report}"
    rescue Errno::ENOENT => error
      raise Error, "dots-check is unavailable: #{error.message}"
    end

    def require_bundle!(destination)
      raise Error, "Handoff not found: #{destination}" unless File.directory?(destination)

      missing = REQUIRED_FILES.reject { |name| File.file?(File.join(destination, name)) }
      raise Error, "Handoff is incomplete; missing: #{missing.join(", ")}" unless missing.empty?
    end
  end

  def self.cli(argv, env: ENV, output: $stdout, error: $stderr)
    operation = argv.shift
    runner = Runner.new(
      tasks_root: "/Volumes/dev/_tasks",
      cloud_root: File.join(Dir.home, "Dropbox", "@docs", "pi-handoffs"),
      scanner_path: File.join(Dir.home, ".dots", ".agents", "skills", "dots-check", "scripts", "scan.rb"),
      session_file: env["PI_SESSION_FILE"],
      session_id: env["PI_SESSION_ID"],
      output: output
    )

    case operation
    when "pass"
      is_sensitive_allowed = argv.last == "--allow-sensitive"
      argv.pop if is_sensitive_allowed
      raise UsageError, "Usage: handit.rb pass <task-folder> <summary-file> [--allow-sensitive]" unless argv.length == 2

      destination = runner.pass(
        argv[0],
        argv[1],
        is_sensitive_allowed: is_sensitive_allowed,
        is_summary_temporary: true
      )
      output.puts "Export completed: #{destination}"
    when "receive"
      raise UsageError, "Usage: handit.rb receive <task-folder>" unless argv.length == 1

      output.puts runner.receive(argv[0])
    when "complete"
      raise UsageError, "Usage: handit.rb complete <task-folder>" unless argv.length == 1

      output.puts "Removed: #{runner.complete(argv[0])}"
    else
      raise UsageError, "Usage: handit.rb <pass|receive|complete> ..."
    end

    0
  rescue UsageError => exception
    error.puts exception.message
    2
  rescue Error => exception
    error.puts exception.message
    1
  end
end

exit Handit.cli(ARGV) if $PROGRAM_NAME == __FILE__
