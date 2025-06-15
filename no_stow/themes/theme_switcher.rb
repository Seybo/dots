#!/usr/bin/env ruby
# This script works best when invoked by zsh alias 'theme' which also re-sources .zshrc and .tmux.conf
# frozen_string_literal: true

THEMES_DIR  = File.expand_path('~/.dots/no_stow/themes')
ACTIVE_DIR  = File.join(THEMES_DIR, 'active')

abort "Usage: #{$0} <theme_name>" unless ARGV[0]
theme = ARGV[0].strip

abort "You cannot set the theme to 'active'." if theme == 'active'

theme_dir = File.join(THEMES_DIR, theme)
abort "Theme '#{theme}' does not exist (expected directory: #{theme_dir})" unless Dir.exist?(theme_dir)

# Remove all previous theme files in active/
Dir.glob(File.join(ACTIVE_DIR, '*')).each do |file|
  File.delete(file)
end

# Copy all theme files from chosen theme to active/
Dir.glob(File.join(theme_dir, '*')).each do |src|
  fname = File.basename(src)
  next if ['.', '..'].include?(fname)

  dst = File.join(ACTIVE_DIR, fname)
  File.write(dst, File.read(src))
end

# This script works best when invoked by zsh alias 'theme' which also re-sources .zshrc and .tmux.conf
