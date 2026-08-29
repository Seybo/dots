#!/usr/bin/env ruby
# frozen_string_literal: true

OMA_DESTINATION = 'oma'
THEME_NAME = /\A[a-z0-9][a-z0-9._-]*\z/

abort "Usage: #{$PROGRAM_NAME} <theme_name>" unless ARGV.length == 1
theme = ARGV.first.strip
abort 'Theme name is invalid.' unless theme.match?(THEME_NAME)
abort 'theme_ssh must run on squirrel.' unless ENV['MACHINE_NAME'] == 'squirrel'

selector = File.expand_path('~/.dots/themes/terminal_theme_switcher.rb')
remote_selector = '$HOME/.dots/themes/terminal_theme_switcher.rb'

def run!(*command)
  return if system(*command)

  abort "Command failed: #{command.first}"
end

def remote_command(selector, theme, is_check:)
  action = is_check ? '--check ' : ''
  %(MACHINE_NAME=oma STOW_DIR="$HOME/.omadots" "#{selector}" #{action}#{theme})
end

run!(selector, '--check', theme)
run!('ssh', OMA_DESTINATION, remote_command(remote_selector, theme, is_check: true))
run!('ssh', OMA_DESTINATION, remote_command(remote_selector, theme, is_check: false))
run!(selector, theme)

puts "SSH terminal theme: #{theme}"
