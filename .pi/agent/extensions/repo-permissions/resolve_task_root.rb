# frozen_string_literal: true

require 'yaml'

def expand_root(raw_root, dev_root, stow_dir)
  return stow_dir if raw_root == '$STOW_DIR'
  return File.join(stow_dir, raw_root.delete_prefix('$STOW_DIR/')) if raw_root.start_with?('$STOW_DIR/')
  return File.expand_path(raw_root) if raw_root == '~' || raw_root.start_with?('~/')
  return raw_root if raw_root.start_with?('/')

  File.expand_path(raw_root, dev_root)
end

def ordinal?(name)
  match = /\A([1-9]\d*)(st|nd|rd|th)\z/.match(name)
  return false unless match

  number = match[1].to_i
  suffix = if (11..13).cover?(number % 100)
             'th'
           else
             { 1 => 'st', 2 => 'nd', 3 => 'rd' }.fetch(number % 10, 'th')
           end
  match[2] == suffix
end

def project_matches?(layout, project_root, primary_root)
  case layout
  when 'direct'
    primary_root == project_root
  when 'ordinal_workspaces'
    File.dirname(primary_root) == project_root && ordinal?(File.basename(primary_root))
  else
    raise "Unsupported checkout layout: #{layout}"
  end
end

registry_path, primary_root, dev_root, stow_dir = ARGV
abort 'Usage: resolve_task_root.rb REGISTRY PRIMARY_ROOT DEV_ROOT STOW_DIR' unless stow_dir

registry = YAML.safe_load_file(registry_path, aliases: false)
projects = registry.fetch('projects')
primary_root = File.realpath(primary_root)

roots = projects.filter_map do |_name, config|
  layout = config.fetch('checkout_layout')
  raw_root = config.fetch(layout == 'direct' ? 'checkout_path' : 'code_root')
  project_root = File.realpath(expand_root(raw_root, dev_root, stow_dir))

  File.join(project_root, '_tasks') if project_matches?(layout, project_root, primary_root)
rescue Errno::ENOENT
  nil
end.uniq

raise 'Primary repository matches multiple registered projects' if roots.length > 1

puts roots.first if roots.first
