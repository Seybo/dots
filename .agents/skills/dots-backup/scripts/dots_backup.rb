#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "optparse"
require "time"
require "yaml"

EXIT_USAGE = 2
UNKNOWN = "unknown"
SUPPORTED_RUN_TYPES = ["dry-run", "backup", "check"].freeze

BackupEntry = Struct.new(:name, :tool, :included, :excluded, :last_run, :status, :volume_path, keyword_init: true)
OverlapFinding = Struct.new(:first_entry, :first_path, :second_entry, :second_path, keyword_init: true)

class BackupRunner
  def initialize(inventory_path:, status_dir:, name:, run_type:, input: $stdin, output: $stdout)
    @inventory_path = inventory_path
    @status_dir = status_dir
    @name = name
    @run_type = run_type
    @input = input
    @output = output
  end

  def run
    validate_run_type!
    command = command_for_entry

    @output.puts "Command: #{command}"
    @output.print "Type yes to run: "
    confirmation = @input.gets&.strip
    unless confirmation == "yes"
      @output.puts "Run cancelled"
      return 1
    end

    started_at = Time.now.utc.iso8601
    stdout, stderr, status = Open3.capture3(command)
    finished_at = Time.now.utc.iso8601
    persist_status(command, stdout, stderr, status.exitstatus, started_at, finished_at)
    status.success? ? 0 : 1
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

  def persist_status(command, stdout, stderr, exit_status, started_at, finished_at)
    FileUtils.mkdir_p(@status_dir)
    base = safe_filename("#{@name}-#{@run_type}")
    stdout_log = File.join(@status_dir, "#{base}.stdout.log")
    stderr_log = File.join(@status_dir, "#{base}.stderr.log")
    status_path = File.join(@status_dir, "#{base}.json")
    run_status = exit_status.zero? ? "success" : "failed"

    File.write(stdout_log, stdout)
    File.write(stderr_log, stderr)
    File.write(status_path, JSON.pretty_generate({
      "name" => @name,
      "run_type" => @run_type,
      "command" => command,
      "started_at" => started_at,
      "finished_at" => finished_at,
      "exit_status" => exit_status,
      "status" => run_status,
      "stdout_log" => stdout_log,
      "stderr_log" => stderr_log
    }) + "\n")
  end

  def safe_filename(value)
    value.to_s.downcase.gsub(/[^a-z0-9_-]+/, "-").gsub(/-+/, "-").gsub(/\A-|\-\z/, "")
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
  opts.on("--run NAME", "Run a stored backup entry command after confirmation") { |name| options[:run_name] = name }
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
