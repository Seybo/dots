#!/usr/bin/env ruby
# frozen_string_literal: true

require 'optparse'
require 'open3'
require 'set'
require 'shellwords'

EXIT_USAGE = 2
MAX_FILE_BYTES = 1_000_000
ENTROPY_THRESHOLD = 4.2
ENTROPY_MIN_LEN = 32
ENTROPY_MAX_LEN = 128

Rule = Struct.new(:name, :regex)
Finding = Struct.new(:rule, :path, :line, :snippet)
Target = Struct.new(:lines, :source)

RULES = [
  Rule.new('aws_access_key', /AKIA[0-9A-Z]{16}/),
  Rule.new('aws_secret', /\baws[\w-]{0,20}(?:secret|access)[\w-]{0,20}key(?:_id)?\b["']?\s*[:=]\s*["']?[0-9A-Za-z\/+]{32,}["']?/i),
  Rule.new('github_token', /gh[pous]_[0-9A-Za-z]{24,}/),
  Rule.new('slack_token', /xox(?:p|b|o|a)-[0-9A-Za-z-]{10,}/),
  Rule.new('stripe_live', /sk_live_[0-9A-Za-z]{16,}/),
  Rule.new('stripe_pk_live', /pk_live_[0-9A-Za-z]{16,}/),
  Rule.new('twilio', /SK[0-9a-fA-F]{32}/),
  Rule.new('google_api', /AIza[0-9A-Za-z\-_]{35}/),
  Rule.new('openai', /sk-[A-Za-z0-9]{32,}/),
  Rule.new('anthropic', /sk-ant-[A-Za-z0-9]{32,}/),
  Rule.new('mistral', /mistral-[a-z]{2,6}-[A-Za-z0-9]{32,}/),
  Rule.new('groq', /gsk_[A-Za-z0-9]{24,}/),
  Rule.new('hf_token', /hf_[A-Za-z0-9]{30,}/),
  Rule.new('vercel', /vercel\.[A-Za-z0-9]{40}/i),
  Rule.new('supabase', /supabase\.[A-Za-z0-9]{40}/i),
  Rule.new('cloudflare', /cf_[A-Za-z0-9]{30,}/),
  Rule.new('jwt', /eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}/),
  Rule.new('age_secret_key', /AGE-SECRET-KEY-1[0-9A-Z]{58}/i),
  Rule.new('pem_private_key', /-----BEGIN (?:RSA |DSA |EC |OPENSSH |PGP |ENCRYPTED )?PRIVATE KEY-----/)
].freeze

CANDIDATE_TOKEN_REGEX = %r{[A-Za-z0-9+/_-]{#{ENTROPY_MIN_LEN},#{ENTROPY_MAX_LEN}}}

options = {
  all: false,
  unstaged: false,
  untracked: false,
  path: nil,
  last_commits: nil
}

parser = OptionParser.new do |opts|
  opts.banner = 'Usage: scan.rb [--all] [--unstaged] [--untracked] [--path GLOB] [--last-commits COUNT]'
  opts.on('--all', 'Scan all tracked files') { options[:all] = true }
  opts.on('--unstaged', 'Scan unstaged tracked changes, ignoring staged changes and HEAD fallback') { options[:unstaged] = true }
  opts.on('--untracked', 'Include untracked files') { options[:untracked] = true }
  opts.on('--path GLOB', 'Only scan files matching glob') { |g| options[:path] = g }
  opts.on('--last-commits COUNT', '--last COUNT', Integer, 'Scan changed lines in the last COUNT commits') do |count|
    options[:last_commits] = count
  end
  opts.on('-h', '--help', 'Show help') do
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

if options[:last_commits] && options[:last_commits] <= 0
  warn 'Error: --last-commits must be a positive integer'
  warn parser
  exit EXIT_USAGE
end

if options[:last_commits] && (options[:all] || options[:unstaged] || options[:untracked])
  warn 'Error: --last-commits cannot be combined with --all, --unstaged, or --untracked'
  warn parser
  exit EXIT_USAGE
end

if options[:all] && options[:unstaged]
  warn 'Error: --all cannot be combined with --unstaged'
  warn parser
  exit EXIT_USAGE
end

unless system('git rev-parse --is-inside-work-tree > /dev/null 2>&1')
  warn 'Error: not inside a git repository'
  exit EXIT_USAGE
end

repo_root, ok = Open3.capture2('git rev-parse --show-toplevel')
unless ok.success?
  warn 'Error: failed to resolve git repository root'
  exit EXIT_USAGE
end

Dir.chdir(repo_root.strip)

def capture(cmd)
  stdout, status = Open3.capture2(cmd)
  [stdout, status.success?]
end

def parse_changed_lines(diff_cmd)
  out, ok = capture(diff_cmd)
  raise "#{diff_cmd} failed" unless ok

  changes = Hash.new { |h, k| h[k] = Set.new }
  current_path = nil
  new_lineno = nil

  out.each_line do |line|
    case line
    when /^\+\+\+\s+(.*)/
      path = Regexp.last_match(1)
      next if path == 'b/dev/null'

      current_path = path.sub(%r{\Ab/}, '')
    when /^@@ .*\+(\d+)(?:,(\d+))? @@/
      new_lineno = Regexp.last_match(1).to_i
    when /^\+/
      next if line.start_with?('+++')

      if current_path && new_lineno
        changes[current_path] << new_lineno
        new_lineno += 1
      end
    when /^-/
      # deletion: do not advance new_lineno because it applies to old file
      next
    else
      new_lineno += 1 if new_lineno
    end
  end

  changes
end

def filter_targets(targets, glob)
  return targets unless glob

  targets.select { |path, _| File.fnmatch?(glob, path, File::FNM_PATHNAME | File::FNM_EXTGLOB) }
end

def collect_targets(options)
  targets = {}

  if options[:all]
    out, ok = capture('git ls-files')
    raise 'git ls-files failed' unless ok

    out.lines.map(&:chomp).each { |f| targets[f] = Target.new(:full, :worktree) unless f.empty? }
  else
    staged, = capture('git diff --cached --name-only')
    unstaged, = capture('git diff --name-only')
    diff_cmd = nil
    source = nil

    if options[:unstaged]
      if !unstaged.strip.empty?
        diff_cmd = 'git diff -U0'
        source = :worktree
      end
    elsif !staged.strip.empty?
      diff_cmd = 'git diff --cached -U0'
      source = :index
    elsif !unstaged.strip.empty?
      diff_cmd = 'git diff -U0'
      source = :worktree
    else
      head_exists = system('git rev-parse --verify HEAD > /dev/null 2>&1')
      if head_exists
        diff_cmd = 'git show --format= --unified=0 HEAD'
        source = 'HEAD'
      end
    end

    if diff_cmd
      parse_changed_lines(diff_cmd).each do |path, lines|
        targets[path] = Target.new(lines, source)
      end
    end
  end

  if options[:untracked]
    untracked, = capture('git ls-files --others --exclude-standard')
    untracked.lines.map(&:chomp).each { |f| targets[f] = Target.new(:full, :worktree) unless f.empty? }
  end

  filter_targets(targets, options[:path])
end

def collect_commit_targets(ref, path_glob)
  targets = {}
  diff_cmd = "git show --format= --unified=0 #{Shellwords.escape(ref)}"

  parse_changed_lines(diff_cmd).each do |path, lines|
    targets[path] = Target.new(lines, ref)
  end

  filter_targets(targets, path_glob)
end

def binary_file?(path)
  File.open(path, 'rb') do |f|
    chunk = f.read(8000) || ''
    return true if chunk.include?("\x00")
  end
  false
rescue StandardError
  false
end

def blob_content(path, source)
  ref = source == :index ? ":#{path}" : "#{source}:#{path}"
  content, status = Open3.capture2('git', 'show', ref)
  return nil unless status.success?

  content
end

def entropy(str)
  counts = str.each_char.tally
  len = str.length.to_f
  counts.values.reduce(0.0) do |h, count|
    p = count / len
    h - p * Math.log2(p)
  end
end

def high_entropy_tokens(line)
  tokens = []
  line.scan(CANDIDATE_TOKEN_REGEX) do |token|
    next if token.length < ENTROPY_MIN_LEN || token.length > ENTROPY_MAX_LEN

    h = entropy(token)
    tokens << token if h >= ENTROPY_THRESHOLD
  end
  tokens
end

def sanitize_snippet(line)
  snippet = line.chomp.strip
  snippet = snippet.gsub(%r{/Users/[^/\s:'"]+}, '/Users/<redacted>')
  snippet = snippet.gsub(%r{/Volumes/[^/\s:'"]+}, '/Volumes/<redacted>')
  snippet.length > 180 ? snippet[0, 180] + '…' : snippet
end

def redact_regex_matches(line, regex)
  sanitize_snippet(line.gsub(regex, '<redacted>'))
end

def print_targets(targets)
  puts "Checking files (#{targets.size}):"
  targets.keys.sort.each do |path|
    puts "- #{path}"
  end
end

def scan_targets(targets)
  findings = []

  targets.each do |path, target|
    lines = target.lines
    content = nil

    if target.source == :worktree
      next unless File.file?(path)

      begin
        size = File.size(path)
      rescue Errno::ENOENT
        next
      end

      if size > MAX_FILE_BYTES
        warn "Skipping #{path} (size > #{MAX_FILE_BYTES} bytes)"
        next
      end

      if binary_file?(path)
        warn "Skipping #{path} (binary)"
        next
      end
    else
      content = blob_content(path, target.source)
      next unless content

      if content.bytesize > MAX_FILE_BYTES
        warn "Skipping #{path} (size > #{MAX_FILE_BYTES} bytes)"
        next
      end

      if content.include?("\x00")
        warn "Skipping #{path} (binary)"
        next
      end
    end

    begin
      each_line = content ? content.each_line : File.foreach(path)
      each_line.with_index(1) do |line, lineno|
        next unless lines == :full || lines.include?(lineno)

        RULES.each do |rule|
          if line.match?(rule.regex)
            findings << Finding.new(rule.name, path, lineno, redact_regex_matches(line, rule.regex))
          end
        end

        high_entropy_tokens(line).each do |token|
          findings << Finding.new('high_entropy', path, lineno, sanitize_snippet(line.sub(token, '<redacted>')))
        end
      end
    rescue StandardError => e
      warn "Error reading #{path}: #{e.message}"
    end
  end

  findings
end

def print_findings(findings)
  puts "🚨 Findings (#{findings.size}):"
  findings.each do |f|
    puts "- [#{f.rule}] #{f.path}:#{f.line} :: #{f.snippet}"
  end
end

def commit_subject(ref)
  subject, ok = capture("git log -1 --format=%s #{Shellwords.escape(ref)}")
  ok ? subject.strip : ''
end

def commit_short(ref)
  short, ok = capture("git rev-parse --short #{Shellwords.escape(ref)}")
  ok ? short.strip : ref[0, 7]
end

if options[:last_commits]
  commits_out, ok = capture("git rev-list --max-count=#{options[:last_commits]} HEAD")
  unless ok
    warn 'Error: failed to list commits'
    exit EXIT_USAGE
  end

  commits = commits_out.lines.map(&:chomp).reject(&:empty?)
  if commits.empty?
    puts 'No commits to scan.'
    exit 0
  end

  puts "Checking commits (#{commits.size}):"
  all_findings = []

  commits.each do |ref|
    puts "===== #{commit_short(ref)} #{commit_subject(ref)} ====="
    targets = collect_commit_targets(ref, options[:path])

    if targets.empty?
      puts 'No files to scan (diff is empty).'
      next
    end

    print_targets(targets)
    findings = scan_targets(targets)
    if findings.empty?
      puts '✅ No findings'
    else
      print_findings(findings)
      all_findings.concat(findings)
    end
  end

  if all_findings.empty?
    puts "✅ No findings across #{commits.size} commits"
    exit 0
  end

  puts "🚨 Findings across #{commits.size} commits: #{all_findings.size}"
  exit 1
end

targets = collect_targets(options)
if targets.empty?
  puts 'No files to scan (diff is empty).'
  exit 0
end

print_targets(targets)
findings = scan_targets(targets)

if findings.empty?
  puts '✅ No findings'
  exit 0
end

print_findings(findings)
exit 1
