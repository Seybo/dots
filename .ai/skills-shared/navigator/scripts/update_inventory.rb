#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'yaml'
require 'time'
require 'fileutils'
require 'set'

HOME_DIR = Dir.home
SKILL_ROOT = File.expand_path('..', __dir__)
REPO_ROOT = File.expand_path('../../../..', __dir__)
REFERENCES_DIR = File.join(SKILL_ROOT, 'references')

GENERATED_INVENTORY_PATH = File.join(REFERENCES_DIR, 'inventory.generated.md')
GENERATED_UNCATEGORIZED_PATH = File.join(REFERENCES_DIR, 'uncategorized.generated.md')
CAPABILITY_MAP_PATH = File.join(REFERENCES_DIR, 'capability-map.md')
ALIASES_PATH = File.join(REFERENCES_DIR, 'aliases.md')

Skill = Struct.new(:name, :description, :path, :is_command_only, :is_hidden, keyword_init: true)
Prompt = Struct.new(:command, :description, :argument_hint, :path, keyword_init: true)
Abbreviation = Struct.new(:name, :description, :path, keyword_init: true)

def expand_path(path)
  expanded = path.to_s.sub(/\A~(?=\/|\z)/, HOME_DIR)
  File.expand_path(expanded, REPO_ROOT)
end

def display_path(path)
  expanded = File.expand_path(path)
  repo_prefix = REPO_ROOT.end_with?('/') ? REPO_ROOT : "#{REPO_ROOT}/"
  home_prefix = HOME_DIR.end_with?('/') ? HOME_DIR : "#{HOME_DIR}/"

  if expanded.start_with?(repo_prefix)
    expanded.delete_prefix(repo_prefix)
  elsif expanded == HOME_DIR
    '~'
  elsif expanded.start_with?(home_prefix)
    "~/#{expanded.delete_prefix(home_prefix)}"
  else
    expanded
  end
end

def read_json(path)
  return {} unless File.file?(path)

  JSON.parse(File.read(path, encoding: 'UTF-8'))
rescue JSON::ParserError
  {}
end

def settings_paths
  [
    File.join(HOME_DIR, '.pi/agent/settings.json'),
    File.join(REPO_ROOT, '.pi/agent/settings.json')
  ]
end

def settings_values(key)
  settings_paths.flat_map { |path| Array(read_json(path)[key]) }
end

def frontmatter(path)
  text = File.read(path, encoding: 'UTF-8')
  match = text.match(/\A---\s*\n(.*?)\n---\s*\n/m)
  return [{}, text] unless match

  data = YAML.safe_load(match[1], aliases: true) || {}
  body = text.sub(/\A---\s*\n.*?\n---\s*\n/m, '')
  [data, body]
rescue StandardError => error
  [{ 'parse_error' => "#{error.class}: #{error.message}" }, '']
end

def first_body_line(body)
  body.each_line.map(&:strip).find { |line| !line.empty? } || ''
end

def normalize_text(value, max_length = 420)
  text = value.to_s.gsub(/\s+/, ' ').strip
  return text if text.length <= max_length

  "#{text[0, max_length - 1].rstrip}…"
end

def escape_md(value)
  normalize_text(value).gsub('|', '\\|')
end

def unique_existing(paths)
  paths.map { |path| expand_path(path) }.select { |path| File.exist?(path) }.uniq
end

def skill_files_from_directory(path, include_root_markdown: false)
  return [] unless File.directory?(path)

  files = Dir.glob(File.join(path, '**', 'SKILL.md'))
  files += Dir.glob(File.join(path, '*.md')) if include_root_markdown
  files.uniq
end

def configured_skill_files
  settings_values('skills').flat_map do |entry|
    path = expand_path(entry)
    if File.file?(path)
      [path]
    elsif File.directory?(path)
      skill_files_from_directory(path, include_root_markdown: true)
    else
      []
    end
  end
end

def discover_skills
  default_files = []
  default_files += skill_files_from_directory(File.join(HOME_DIR, '.pi/agent/skills'), include_root_markdown: true)
  default_files += skill_files_from_directory(File.join(HOME_DIR, '.agents/skills'))
  default_files += skill_files_from_directory(File.join(REPO_ROOT, '.agents/skills'))
  default_files += skill_files_from_directory(File.join(HOME_DIR, '.ai/skills-shared'))
  default_files += configured_skill_files

  default_files.uniq.filter_map do |path|
    data, = frontmatter(path)
    name = data['name'] || if File.basename(path) == 'SKILL.md'
                             File.basename(File.dirname(path))
                           else
                             File.basename(path, '.md')
                           end
    next if name.to_s.empty?

    description = data['description'] || ''
    Skill.new(
      name: name.to_s,
      description: normalize_text(description),
      path: path,
      is_command_only: description.to_s.match?(/command-only|invoke only/i),
      is_hidden: data['disable-model-invocation'] == true
    )
  end.sort_by { |skill| [skill.name, display_path(skill.path)] }
end

def prompt_files_from_directory(path)
  return [] unless File.directory?(path)

  Dir.glob(File.join(path, '*.md'))
end

def configured_prompt_files
  settings_values('prompts').flat_map do |entry|
    path = expand_path(entry)
    if File.file?(path)
      [path]
    elsif File.directory?(path)
      prompt_files_from_directory(path)
    else
      []
    end
  end
end

def discover_prompts
  files = []
  files += prompt_files_from_directory(File.join(HOME_DIR, '.pi/agent/prompts'))
  files += prompt_files_from_directory(File.join(REPO_ROOT, '.pi/prompts'))
  files += configured_prompt_files

  files.uniq.filter_map do |path|
    data, body = frontmatter(path)
    command = "/#{File.basename(path, '.md')}"
    description = data['description'] || first_body_line(body)
    Prompt.new(
      command: command,
      description: normalize_text(description),
      argument_hint: data['argument-hint'].to_s,
      path: path
    )
  end.sort_by { |prompt| [prompt.command, display_path(prompt.path)] }
end

def abbreviation_sources
  unique_existing([
    File.join(HOME_DIR, '.pi/agent/AGENTS.md'),
    File.join(REPO_ROOT, 'AGENTS.md'),
    File.join(REPO_ROOT, '.ai/rules/abbreviations.md'),
    File.join(HOME_DIR, '.ai/rules/abbreviations.md')
  ])
end

def discover_abbreviations
  abbreviations = []

  abbreviation_sources.each do |path|
    File.readlines(path, encoding: 'UTF-8').each do |line|
      match = line.match(/^\s*-\s*`([^`]+)`\s*[—-]\s*(.+)$/)
      next unless match

      abbreviations << Abbreviation.new(
        name: match[1],
        description: normalize_text(match[2]),
        path: path
      )
    end
  end

  seen = Set.new
  abbreviations.select { |item| seen.add?([item.name, item.description]) }
               .sort_by { |item| [item.name, display_path(item.path)] }
end

def generated_header(title)
  <<~MD
    # #{title}

    Generated by `scripts/update_inventory.rb`.
    Do not edit this file by hand.

  MD
end

def build_inventory(skills, prompts, abbreviations)
  lines = [generated_header('Navigator Inventory')]

  lines << "## Skill sources scanned\n\n"
  skill_source_dirs = unique_existing([
    File.join(HOME_DIR, '.pi/agent/skills'),
    File.join(HOME_DIR, '.agents/skills'),
    File.join(REPO_ROOT, '.agents/skills'),
    File.join(HOME_DIR, '.ai/skills-shared'),
    *settings_values('skills')
  ])
  if skill_source_dirs.empty?
    lines << "- None found.\n\n"
  else
    skill_source_dirs.each { |path| lines << "- `#{display_path(path)}`\n" }
    lines << "\n"
  end

  lines << "## Skills\n\n"
  if skills.empty?
    lines << "No skills found.\n\n"
  else
    lines << "| Command | Source | Notes | Description |\n"
    lines << "|---|---|---|---|\n"
    skills.each do |skill|
      notes = []
      notes << 'command-only' if skill.is_command_only
      notes << 'hidden from auto invocation' if skill.is_hidden
      lines << "| `/skill:#{escape_md(skill.name)}` | `#{escape_md(display_path(skill.path))}` | #{escape_md(notes.join(', '))} | #{escape_md(skill.description)} |\n"
    end
    lines << "\n"
  end

  lines << "## Prompt template commands\n\n"
  if prompts.empty?
    lines << "No prompt template commands found in scanned locations.\n\n"
  else
    lines << "| Command | Arguments | Source | Description |\n"
    lines << "|---|---|---|---|\n"
    prompts.each do |prompt|
      lines << "| `#{escape_md(prompt.command)}` | #{escape_md(prompt.argument_hint)} | `#{escape_md(display_path(prompt.path))}` | #{escape_md(prompt.description)} |\n"
    end
    lines << "\n"
  end

  lines << "## Abbreviations\n\n"
  if abbreviations.empty?
    lines << "No abbreviations found in scanned locations.\n\n"
  else
    lines << "| Abbreviation | Source | Meaning |\n"
    lines << "|---|---|---|\n"
    abbreviations.each do |abbr|
      lines << "| `#{escape_md(abbr.name)}` | `#{escape_md(display_path(abbr.path))}` | #{escape_md(abbr.description)} |\n"
    end
    lines << "\n"
  end

  lines << "## Notes\n\n"
  lines << "- Extension commands and built-in Pi slash commands may not be fully discoverable from static files. Check Pi autocomplete or extension docs when needed.\n"
  lines << "- For exact usage, read the source file listed above.\n"

  lines.join
end

def categorization_text
  [CAPABILITY_MAP_PATH, ALIASES_PATH].select { |path| File.file?(path) }
                                  .map { |path| File.read(path, encoding: 'UTF-8') }
                                  .join("\n")
                                  .downcase
end

def uncategorized_items(skills, prompts, abbreviations)
  text = categorization_text

  skill_items = skills.reject { |skill| text.include?(skill.name.downcase) }
                      .map { |skill| "- Skill `/skill:#{skill.name}` — `#{display_path(skill.path)}`" }
  prompt_items = prompts.reject { |prompt| text.include?(prompt.command.downcase) }
                        .map { |prompt| "- Prompt `#{prompt.command}` — `#{display_path(prompt.path)}`" }
  abbreviation_items = abbreviations.reject { |abbr| text.include?(abbr.name.downcase) }
                                    .map { |abbr| "- Abbreviation `#{abbr.name}` — `#{display_path(abbr.path)}`" }

  { skills: skill_items, prompts: prompt_items, abbreviations: abbreviation_items }
end

def build_uncategorized(skills, prompts, abbreviations)
  items = uncategorized_items(skills, prompts, abbreviations)
  lines = [generated_header('Navigator Uncategorized Items')]

  if items.values.all?(&:empty?)
    lines << "All scanned skills, prompt commands, and abbreviations appear in `capability-map.md` or `aliases.md`.\n"
    return lines.join
  end

  lines << "Review these items and add useful ones to `capability-map.md` and/or `aliases.md`.\n\n"
  {
    'Skills' => items[:skills],
    'Prompt template commands' => items[:prompts],
    'Abbreviations' => items[:abbreviations]
  }.each do |title, entries|
    lines << "## #{title}\n\n"
    if entries.empty?
      lines << "None.\n\n"
    else
      lines << entries.join("\n")
      lines << "\n\n"
    end
  end

  lines.join
end

def write_if_changed(path, content)
  existing = File.file?(path) ? File.read(path, encoding: 'UTF-8') : nil
  return false if existing == content

  FileUtils.mkdir_p(File.dirname(path))
  File.write(path, content)
  true
end

skills = discover_skills
prompts = discover_prompts
abbreviations = discover_abbreviations

changed = []
changed << GENERATED_INVENTORY_PATH if write_if_changed(GENERATED_INVENTORY_PATH, build_inventory(skills, prompts, abbreviations))
changed << GENERATED_UNCATEGORIZED_PATH if write_if_changed(GENERATED_UNCATEGORIZED_PATH, build_uncategorized(skills, prompts, abbreviations))

puts "Navigator inventory: #{skills.size} skills, #{prompts.size} prompt commands, #{abbreviations.size} abbreviations."
if changed.empty?
  puts 'No files changed.'
else
  puts 'Updated:'
  changed.each { |path| puts "- #{display_path(path)}" }
end
