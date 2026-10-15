#!/usr/bin/env ruby
# This script works best when invoked by zsh alias 'theme'
# frozen_string_literal: true

require 'fileutils'

THEMES_DIR = File.expand_path("#{ENV['STOW_DIR']}/themes")
ACTIVE_DIR = File.join(THEMES_DIR, 'active')
ZELLIJ_CONFIG = File.expand_path('~/.config/zellij/config.kdl')

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

# Pi only hot-reloads themes from each profile's native themes directory.
pi_theme = File.join(ACTIVE_DIR, 'pi.json')
if File.file?(pi_theme)
  %w[work personal].each do |profile|
    directory = File.expand_path("~/.pi/#{profile}/themes")
    FileUtils.mkdir_p(directory)
    File.write(File.join(directory, 'env-active.json'), File.read(pi_theme))
  end
end

# Touch Zellij config so running sessions notice config/theme changes.
# Zellij watches the active config file, but not necessarily external theme files.
File.utime(Time.now, Time.now, ZELLIJ_CONFIG) if File.exist?(ZELLIJ_CONFIG)

# This script works best when invoked by zsh alias 'theme'
