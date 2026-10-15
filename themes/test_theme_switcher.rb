# frozen_string_literal: true

require 'fileutils'
require 'minitest/autorun'
require 'open3'
require 'tmpdir'

# Exercise the real switcher with an isolated home and dotfiles repository.
class ThemeSwitcherTest < Minitest::Test
  ROOT = File.expand_path('..', __dir__)
  SWITCHER = File.join(__dir__, 'theme_switcher.rb')

  def setup
    @directory = Dir.mktmpdir('theme-switcher-', File.join(ROOT, 'agents_tmp'))
    @home = File.join(@directory, 'home')
    @dots = File.join(@directory, 'dots')
    FileUtils.mkdir_p([@home, File.join(@dots, 'themes/active')])
    %w[nordfox everforest-hard-light].each do |name|
      destination = File.join(@dots, 'themes', name)
      FileUtils.mkdir_p(destination)
      FileUtils.cp(File.join(__dir__, name, 'pi.json'), destination)
    end
  end

  def teardown
    FileUtils.remove_entry(@directory)
  end

  def test_both_profiles_follow_theme_switches
    %w[nordfox everforest-hard-light nordfox].each do |name|
      run_switcher(name)
      expected = File.read(File.join(__dir__, name, 'pi.json'))
      %w[work personal].each do |profile|
        assert_equal expected, File.read(profile_theme(profile))
      end
    end
  end

  def test_theme_without_pi_colors_keeps_last_valid_pi_theme
    run_switcher('nordfox')
    FileUtils.mkdir_p(File.join(@dots, 'themes/without-pi'))
    run_switcher('without-pi')

    %w[work personal].each do |profile|
      assert_equal File.read(File.join(__dir__, 'nordfox/pi.json')), File.read(profile_theme(profile))
    end
  end

  def test_invalid_theme_does_not_create_profile_files
    _output, error, status = capture_switcher('missing')
    refute status.success?
    assert_includes error, "Theme 'missing' does not exist"
    %w[work personal].each do |profile|
      refute File.exist?(profile_theme(profile))
    end
  end

  private

  def profile_theme(profile)
    File.join(@home, '.pi', profile, 'themes/env-active.json')
  end

  def capture_switcher(name)
    Open3.capture3({ 'HOME' => @home, 'STOW_DIR' => @dots }, 'ruby', SWITCHER, name)
  end

  def run_switcher(name)
    _output, error, status = capture_switcher(name)
    assert status.success?, error
  end
end
