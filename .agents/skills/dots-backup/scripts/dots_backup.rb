#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "optparse"
require "rbconfig"
require "shellwords"
require "time"
require "yaml"

EXIT_USAGE = 2
UNKNOWN = "unknown"
SUPPORTED_RUN_TYPES = ["dry-run", "backup", "check"].freeze

BackupEntry = Struct.new(:name, :tool, :included, :excluded, :last_run, :status, :volume_path, keyword_init: true)
OverlapFinding = Struct.new(:first_entry, :first_path, :second_entry, :second_path, keyword_init: true)

class BackupRunner
  def initialize(inventory_path:, status_dir:, name:, run_type:, output: $stdout, repo_root: Dir.pwd)
    @inventory_path = File.expand_path(inventory_path)
    @status_dir = File.expand_path(status_dir)
    @name = name
    @run_type = run_type
    @output = output
    @repo_root = File.expand_path(repo_root)
  end

  def run
    validate_run_type!
    command = command_for_entry
    launch_in_sibling_pane(command)
  rescue KeyError, ArgumentError => e
    warn "Error: #{e.message}"
    EXIT_USAGE
  end

  private

  def validate_run_type!
    return if SUPPORTED_RUN_TYPES.include?(@run_type)

    raise ArgumentError, "supported run types are dry-run, backup, check"
  end

  def command_for_entry
    entry = Array(inventory["active_backups"]).find { |candidate| candidate["name"] == @name }
    raise KeyError, "backup entry not found: #{@name}" unless entry

    command = entry.dig("commands", @run_type)
    raise KeyError, "#{@name} has no #{@run_type} command" unless command

    command
  end

  def inventory
    @inventory ||= YAML.safe_load_file(@inventory_path, permitted_classes: [], aliases: false) || {}
  end

  def launch_in_sibling_pane(command)
    target_pane = sibling_pane
    raise ArgumentError, "no sibling tmux pane available for visible backup run" unless target_pane

    script_path = write_pane_script(command)
    tmux_command = "bash #{script_path.shellescape}"

    @output.puts "Command: #{command}"
    @output.puts "Launching in tmux pane #{target_pane}"
    @output.puts "Pane script: #{script_path}"
    stdout, status = Open3.capture2e("tmux", "send-keys", "-t", target_pane, tmux_command, "C-m")
    raise ArgumentError, "tmux send-keys failed: #{stdout.strip}" unless status.success?

    @output.puts "Run is visible in pane #{target_pane}. Status/logs will be written under #{display_path(@status_dir)} when it finishes."
    0
  end

  def sibling_pane
    current = current_pane
    return unless current

    stdout, status = Open3.capture2e("tmux", "list-panes", "-F", "#{pane_id_format} #{pane_index_format}")
    return unless status.success?

    stdout.lines.map(&:strip).reject(&:empty?).map { |line| line.split.first }.find { |pane| pane != current }
  end

  def current_pane
    return unless ENV["TMUX"] && ENV["TMUX_PANE"]

    ENV.fetch("TMUX_PANE")
  end

  def pane_id_format
    '#{pane_id}'
  end

  def pane_index_format
    '#{pane_index}'
  end

  def write_pane_script(command)
    FileUtils.mkdir_p(@status_dir)
    base = safe_filename("#{@name}-#{@run_type}")
    combined_log = File.join(@status_dir, "#{base}.log")
    stdout_log = File.join(@status_dir, "#{base}.stdout.log")
    stderr_log = File.join(@status_dir, "#{base}.stderr.log")
    status_path = File.join(@status_dir, "#{base}.json")
    script_path = File.join(@status_dir, "#{base}.run.sh")

    File.write(script_path, pane_script(command, combined_log, stdout_log, stderr_log, status_path))
    FileUtils.chmod(0o700, script_path)
    script_path
  end

  def pane_script(command, combined_log, stdout_log, stderr_log, status_path)
    <<~BASH
      #!/usr/bin/env bash
      set -u
      cd #{@repo_root.shellescape}
      mkdir -p #{@status_dir.shellescape}
      backup_command=#{command.shellescape}
      combined_log=#{combined_log.shellescape}
      stdout_log=#{stdout_log.shellescape}
      stderr_log=#{stderr_log.shellescape}
      status_path=#{status_path.shellescape}
      started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
      {
        printf '[dots-backup] command: %s\\n' "$backup_command"
        printf '[dots-backup] started_at: %s\\n' "$started_at"
      } | tee "$combined_log"
      bash -o pipefail -c "$backup_command" 2>&1 | tee -a "$combined_log"
      exit_status=${PIPESTATUS[0]}
      finished_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
      if [[ "$exit_status" == "0" ]]; then run_status=success; else run_status=failed; fi
      {
        printf '\\n[dots-backup] finished_at: %s\\n' "$finished_at"
        printf '[dots-backup] status: %s (exit %s)\\n' "$run_status" "$exit_status"
      } | tee -a "$combined_log"
      cp "$combined_log" "$stdout_log"
      : > "$stderr_log"
      BACKUP_NAME=#{@name.shellescape} RUN_TYPE=#{@run_type.shellescape} BACKUP_COMMAND="$backup_command" STARTED_AT="$started_at" FINISHED_AT="$finished_at" EXIT_STATUS="$exit_status" RUN_STATUS="$run_status" STDOUT_LOG="$stdout_log" STDERR_LOG="$stderr_log" COMBINED_LOG="$combined_log" STATUS_PATH="$status_path" #{RbConfig.ruby.shellescape} -rjson -e 'payload = {"name" => ENV.fetch("BACKUP_NAME"), "run_type" => ENV.fetch("RUN_TYPE"), "command" => ENV.fetch("BACKUP_COMMAND"), "started_at" => ENV.fetch("STARTED_AT"), "finished_at" => ENV.fetch("FINISHED_AT"), "exit_status" => ENV.fetch("EXIT_STATUS").to_i, "status" => ENV.fetch("RUN_STATUS"), "stdout_log" => ENV.fetch("STDOUT_LOG"), "stderr_log" => ENV.fetch("STDERR_LOG"), "combined_log" => ENV.fetch("COMBINED_LOG")}; File.write(ENV.fetch("STATUS_PATH"), JSON.pretty_generate(payload) + "\\n")'
      exit "$exit_status"
    BASH
  end

  def safe_filename(value)
    value.to_s.downcase.gsub(/[^a-z0-9_-]+/, "-").gsub(/-+/, "-").gsub(/\A-|\-\z/, "")
  end

  def display_path(path)
    home = File.expand_path("~")
    path == home ? "~" : path.sub(%r{\A#{Regexp.escape(home)}/}, "~/")
  end
end

class DotsBackup
  def initialize(inventory_path:, status_dir: nil)
    @inventory_path = inventory_path
    @status_dir = status_dir
  end

  def run
    entries = active_entries(load_inventory)
    findings = overlap_findings(entries)

    print_report(entries, findings)

    findings.empty? ? 0 : 1
  rescue Errno::ENOENT => e
    warn "Error: #{e.message}"
    EXIT_USAGE
  rescue Psych::SyntaxError => e
    warn "Error: invalid inventory YAML: #{e.message}"
    EXIT_USAGE
  end

  private

  def load_inventory
    YAML.safe_load_file(@inventory_path, permitted_classes: [], aliases: false) || {}
  end

  def active_entries(inventory)
    Array(inventory["active_backups"]).map { |entry| backup_entry(entry) }
  end

  def backup_entry(entry)
    status = status_for(entry.fetch("name", UNKNOWN))
    BackupEntry.new(
      name: entry.fetch("name", UNKNOWN),
      tool: entry.fetch("tool", UNKNOWN),
      included: normalize_list(entry["included"]),
      excluded: normalize_list(entry["excluded"]),
      last_run: present_or_unknown(status&.fetch("finished_at", nil) || entry["last_run"]),
      status: present_or_unknown(status&.fetch("status", nil) || entry["status"]),
      volume_path: entry["volume_path"]
    )
  end

  def status_for(name)
    return unless @status_dir && Dir.exist?(@status_dir)

    statuses = SUPPORTED_RUN_TYPES.filter_map do |run_type|
      path = File.join(@status_dir, "#{safe_filename(name)}-#{run_type}.json")
      next unless File.exist?(path)

      JSON.parse(File.read(path))
    rescue JSON::ParserError
      nil
    end
    statuses.max_by { |status| status.fetch("finished_at", "") }
  end

  def safe_filename(value)
    value.to_s.downcase.gsub(/[^a-z0-9_-]+/, "-").gsub(/-+/, "-").gsub(/\A-|\-\z/, "")
  end

  def normalize_list(value)
    return nil if value.nil?

    Array(value).compact.map(&:to_s)
  end

  def present_or_unknown(value)
    return UNKNOWN if value.nil?

    text = value.to_s.strip
    text.empty? ? UNKNOWN : text
  end

  def overlap_findings(entries)
    findings = []

    entries.combination(2) do |first, second|
      Array(first.included).each do |first_path|
        Array(second.included).each do |second_path|
          next unless path_like?(first_path) && path_like?(second_path)
          next unless overlaps?(first, first_path, second, second_path)

          findings << OverlapFinding.new(
            first_entry: first,
            first_path: first_path,
            second_entry: second,
            second_path: second_path
          )
        end
      end
    end

    findings
  end

  def path_like?(path)
    path.to_s.start_with?("/", "~/", "$HOME/")
  end

  def overlaps?(first, first_path, second, second_path)
    expanded_first = expand_path(first_path)
    expanded_second = expand_path(second_path)

    first_covers_second = path_covers?(expanded_first, expanded_second) && !path_excluded?(first, expanded_second)
    second_covers_first = path_covers?(expanded_second, expanded_first) && !path_excluded?(second, expanded_first)

    first_covers_second || second_covers_first
  end

  def path_excluded?(entry, expanded_candidate)
    Array(entry.excluded).any? do |excluded_path|
      next false unless path_like?(excluded_path)

      path_covers?(expand_path(excluded_path), expanded_candidate)
    end
  end

  def path_covers?(parent, child)
    parent == child || child.start_with?("#{parent}/")
  end

  def expand_path(path)
    File.expand_path(path.to_s.gsub("$HOME", Dir.home))
  end

  def print_report(entries, findings)
    puts "Dots Backup Report"
    puts "Inventory: #{display_path(@inventory_path)}"
    puts
    print_active_backups(entries)
    puts
    print_overlap_findings(findings)
  end

  def print_active_backups(entries)
    puts "Active backups:"

    if entries.empty?
      puts "- none configured"
      return
    end

    entries.each do |entry|
      puts "- #{entry.name} (#{entry.tool})"
      puts "  mounted: #{mounted_label(entry.volume_path)}" if entry.volume_path
      puts "  included folders: #{format_list(entry.included)}"
      puts "  excluded folders: #{format_list(entry.excluded)}"
      puts "  last run: #{entry.last_run}"
      puts "  status: #{entry.status}"
    end
  end

  def print_overlap_findings(findings)
    return if findings.empty?

    puts "Overlap findings:"
    findings.each do |finding|
      puts "- #{finding.first_entry.name} covers #{finding.first_path}; #{finding.second_entry.name} covers #{finding.second_path}"
    end
  end

  def mounted_label(path)
    File.directory?(path) ? "yes" : "no"
  end

  def format_list(value)
    return UNKNOWN if value.nil?
    return "none" if value.empty?

    value.join(", ")
  end

  def display_path(path)
    expanded = File.expand_path(path)
    home = File.expand_path("~")
    expanded == home ? "~" : expanded.sub(%r{\A#{Regexp.escape(home)}/}, "~/")
  end
end

def repo_root_from(start)
  current = File.expand_path(start)

  loop do
    return current if File.directory?(File.join(current, ".git"))

    parent = File.dirname(current)
    raise "could not find repo root from #{start}" if parent == current

    current = parent
  end
end

repo_root = repo_root_from(__dir__)
default_inventory = File.join(repo_root, ".agents", "skills", "dots-backup", "config", "inventory.yml")
default_status_dir = File.join(repo_root, ".agents", "skills", "dots-backup", "state", "runs")
options = {
  inventory_path: default_inventory,
  status_dir: default_status_dir,
  run_name: nil,
  run_type: nil
}

parser = OptionParser.new do |opts|
  opts.banner = "Usage: dots_backup.rb [--inventory PATH] [--status-dir PATH] [--run NAME --type TYPE]"
  opts.on("--inventory PATH", "Inventory YAML path") { |path| options[:inventory_path] = path }
  opts.on("--status-dir PATH", "Skill-managed run status/log directory") { |path| options[:status_dir] = path }
  opts.on("--run NAME", "Run a stored backup entry command") { |name| options[:run_name] = name }
  opts.on("--type TYPE", "Run type: dry-run, backup, or check") { |type| options[:run_type] = type }
  opts.on("-h", "--help", "Show help") do
    puts opts
    exit 0
  end
end

begin
  parser.parse!
rescue OptionParser::ParseError => e
  warn "Error: #{e.message}"
  warn parser
  exit EXIT_USAGE
end

begin
  if options[:run_name] || options[:run_type]
    unless options[:run_name] && options[:run_type]
      warn "Error: --run and --type must be used together"
      exit EXIT_USAGE
    end

    exit BackupRunner.new(
      inventory_path: options.fetch(:inventory_path),
      status_dir: options.fetch(:status_dir),
      name: options.fetch(:run_name),
      run_type: options.fetch(:run_type)
    ).run
  end

  exit DotsBackup.new(inventory_path: options.fetch(:inventory_path), status_dir: options.fetch(:status_dir)).run
rescue StandardError => e
  warn "Error: #{e.message}"
  exit EXIT_USAGE
end
