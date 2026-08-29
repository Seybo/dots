#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'

is_check = ARGV.first == '--check'
expected_arg_count = is_check ? 2 : 1
abort "Usage: #{$PROGRAM_NAME} [--check] <theme_name>" unless ARGV.length == expected_arg_count

theme = ARGV.last.strip
abort 'Theme name is invalid.' unless theme.match?(/\A[a-z0-9][a-z0-9._-]*\z/)

machine_name = ENV.fetch('MACHINE_NAME') { abort 'MACHINE_NAME is required.' }
active_repo = ENV.fetch('STOW_DIR') { abort 'STOW_DIR is required.' }
expected_repo = case machine_name
                when 'squirrel' then File.expand_path('~/.dots')
                when 'oma' then File.expand_path('~/.omadots')
                else abort "Unknown MACHINE_NAME: #{machine_name}"
                end
abort "STOW_DIR must be #{expected_repo} on #{machine_name}." unless File.expand_path(active_repo) == expected_repo

files = machine_name == 'squirrel' ? %w[alacritty.toml] : %w[tmux.conf]
shared_theme_dir = File.expand_path("~/.dots/themes/#{theme}")
missing_files = files.reject { |file| File.file?(File.join(shared_theme_dir, file)) }
abort "Theme '#{theme}' lacks: #{missing_files.join(', ')}" unless missing_files.empty?

active_dir = File.join(active_repo, 'no_stow', 'active_theme')
files.each do |file|
  destination = File.join(active_dir, file)
  abort "Refusing to replace non-symlink: #{destination}" if File.exist?(destination) && !File.symlink?(destination)
end

config = if machine_name == 'squirrel'
           File.expand_path('~/.config/alacritty/alacritty.toml')
         else
           File.expand_path('~/.config/tmux/tmux.conf')
         end
abort "Config not found: #{config}" unless File.file?(config)

if is_check
  puts "SSH theme ready on #{machine_name}: #{theme}"
  exit
end

FileUtils.mkdir_p(active_dir)
files.each do |file|
  source = File.join(shared_theme_dir, file)
  destination = File.join(active_dir, file)
  temporary_link = "#{destination}.tmp-#{Process.pid}"

  begin
    FileUtils.rm_f(temporary_link)
    File.symlink(source, temporary_link)
    File.rename(temporary_link, destination)
  ensure
    FileUtils.rm_f(temporary_link)
  end
end

if machine_name == 'squirrel'
  FileUtils.touch(config)
elsif system('tmux', 'info', out: File::NULL, err: File::NULL)
  abort 'Failed to reload tmux.' unless system('tmux', 'source-file', config)
end

puts "SSH theme on #{machine_name}: #{theme}"
