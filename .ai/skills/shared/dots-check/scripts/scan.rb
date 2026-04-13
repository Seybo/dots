#!/usr/bin/env ruby
# frozen_string_literal: true

require 'optparse'
require 'open3'

EXIT_USAGE = 2
MAX_FILE_BYTES = 1_000_000
ENTROPY_THRESHOLD = 4.2
ENTROPY_MIN_LEN = 32
ENTROPY_MAX_LEN = 128

Rule = Struct.new(:name, :regex)
Finding = Struct.new(:rule, :path, :line, :snippet)

RULES = [
  Rule.new('aws_access_key', /AKIA[0-9A-Z]{16}/),
  Rule.new('aws_secret', %r{(?i)aws(.{0,20})?(secret|access).{0,10}["']?[0-9A-Za-z/+={16,}"']?}),
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
  Rule.new('pem_private_key', /-----BEGIN (?:RSA |DSA |EC |OPENSSH |PGP )?PRIVATE KEY-----/)
].freeze

CANDIDATE_TOKEN_REGEX = %r{[A-Za-z0-9+/_-]{#{ENTROPY_MIN_LEN},#{ENTROPY_MAX_LEN}}}

stow_dir_env = ENV['STOW_DIR']
if stow_dir_env.nil? || stow_dir_env.strip.empty?
  warn 'Error: STOW_DIR is not set'
  exit EXIT_USAGE
end

ROOT_DIR = File.expand_path(stow_dir_env)

unless File.expand_path(Dir.pwd) == ROOT_DIR
  warn "Error: working directory must be STOW_DIR (#{ROOT_DIR}). Current: #{Dir.pwd}"
  exit EXIT_USAGE
end

options = {
  all: false,
  untracked: false,
  path: nil
}

parser = OptionParser.new do |opts|
  opts.banner = 'Usage: scan.rb [--all] [--untracked] [--path GLOB]'
  opts.on('--all', 'Scan all tracked files') { options[:all] = true }
  opts.on('--untracked', 'Include untracked files') { options[:untracked] = true }
  opts.on('--path GLOB', 'Only scan files matching glob') { |g| options[:path] = g }
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

unless system('git rev-parse --is-inside-work-tree > /dev/null 2>&1')
  warn 'Error: not inside a git repository'
  exit EXIT_USAGE
end

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

def collect_targets(options)
  targets = {}

  if options[:all]
    out, ok = capture('git ls-files')
    raise 'git ls-files failed' unless ok

    out.lines.map(&:chomp).each { |f| targets[f] = :full unless f.empty? }
  else
    staged, = capture('git diff --cached --name-only')
    diff_cmd = nil

    if staged.strip.empty?
      head_exists = system('git rev-parse --verify HEAD > /dev/null 2>&1')
      diff_cmd = 'git diff -U0 HEAD' if head_exists
    else
      diff_cmd = 'git diff --cached -U0'
    end

    if diff_cmd
      parse_changed_lines(diff_cmd).each do |path, lines|
        targets[path] = lines
      end
    end
  end

  if options[:untracked]
    untracked, = capture('git ls-files --others --exclude-standard')
    untracked.lines.map(&:chomp).each { |f| targets[f] = :full unless f.empty? }
  end

  if options[:path]
    glob = options[:path]
    targets = targets.select { |path, _| File.fnmatch?(glob, path, File::FNM_PATHNAME | File::FNM_EXTGLOB) }
  end

  targets
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
  snippet.length > 180 ? snippet[0, 180] + '…' : snippet
end

targets = collect_targets(options)
if targets.empty?
  puts 'No files to scan (diff is empty).'
  exit 0
end

puts "Checking files (#{targets.size}):"
targets.keys.sort.each do |path|
  puts "- #{path}"
end

findings = []

targets.each do |path, lines|
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

  begin
    File.foreach(path).with_index(1) do |line, lineno|
      next unless lines == :full || lines.include?(lineno)

      RULES.each do |rule|
        findings << Finding.new(rule.name, path, lineno, sanitize_snippet(line)) if line.match?(rule.regex)
      end

      high_entropy_tokens(line).each do |token|
        findings << Finding.new('high_entropy', path, lineno, sanitize_snippet(line.sub(token, '<redacted>')))
      end
    end
  rescue StandardError => e
    warn "Error reading #{path}: #{e.message}"
  end
end

if findings.empty?
  puts '✅ No findings'
  exit 0
end

puts "🚨 Findings (#{findings.size}):"
findings.each do |f|
  puts "- [#{f.rule}] #{f.path}:#{f.line} :: #{f.snippet}"
end

exit 1
