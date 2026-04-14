# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"
require "securerandom"

class ScanSpec < Minitest::Test
  SCRIPT = File.expand_path("../scripts/scan.rb", __dir__)

  def with_repo
    Dir.mktmpdir("dots-check-") do |dir|
      Dir.chdir(dir) do
        system("git init -q")
        system("git config user.email test@example.com")
        system("git config user.name Test")
        yield dir
      end
    end
  end

  def run_scan(dir, *args)
    Open3.capture3(SCRIPT, *args, chdir: dir)
  end

  def test_detects_github_token_in_staged_file
    with_repo do |dir|
      File.write(File.join(dir, "tok.txt"), "ghp_1234567890abcdef12345678")
      system({"HOME" => dir}, "git", "add", "tok.txt", chdir: dir)
      stdout, _stderr, status = run_scan(dir)
      assert_equal 1, status.exitstatus
      assert_match(/github_token/, stdout)
    end
  end

  def test_only_changed_lines_are_scanned_by_default
    with_repo do |dir|
      path = File.join(dir, "config.txt")
      File.write(path, "token ghp_999999999999999999999999\n")
      system({"HOME" => dir}, "git", "add", "config.txt", chdir: dir)
      system({"HOME" => dir}, "git", "commit", "-m", "init", chdir: dir)

      # Change a separate line; the existing token should not be scanned
      File.open(path, "a") { |f| f.puts "benign change" }

      stdout, _stderr, status = run_scan(dir)
      assert_equal 0, status.exitstatus
      assert_match(/No findings|✅ No findings/, stdout)
      refute_match(/ghp_9999/, stdout)
    end
  end

  def test_all_option_scans_full_files
    with_repo do |dir|
      path = File.join(dir, "config.txt")
      File.write(path, "token ghp_aaaaaaaaaaaaaaaaaaaaaaaa\n")
      system({"HOME" => dir}, "git", "add", "config.txt", chdir: dir)
      system({"HOME" => dir}, "git", "commit", "-m", "init", chdir: dir)

      stdout, _stderr, status = run_scan(dir, "--all")
      assert_equal 1, status.exitstatus
      assert_match(/github_token/, stdout)
    end
  end

  def test_changed_line_with_token_is_detected
    with_repo do |dir|
      path = File.join(dir, "config.txt")
      File.write(path, "benign\n")
      system({"HOME" => dir}, "git", "add", "config.txt", chdir: dir)
      system({"HOME" => dir}, "git", "commit", "-m", "init", chdir: dir)

      File.write(path, "now token ghp_changedtoken12345678901234\n")

      stdout, _stderr, status = run_scan(dir)
      assert_equal 1, status.exitstatus
      assert_match(/github_token/, stdout)
    end
  end

  def test_detects_untracked_file_when_requested
    with_repo do |dir|
      key = ["sk_live_", "abcde", "fghijk", "lmnop", "qrstuv", "wxyz"].join
      File.write(File.join(dir, "untracked.txt"), "sk-live-testkey #{key}")
      stdout, _stderr, status = run_scan(dir, "--untracked")
      assert_equal 1, status.exitstatus
      assert_match(/stripe_live/, stdout)
    end
  end

  def test_detects_entropy_token
    with_repo do |dir|
      token = SecureRandom.alphanumeric(48)
      File.write(File.join(dir, "entropy.txt"), "token #{token}")
      system({"HOME" => dir}, "git", "add", "entropy.txt", chdir: dir)
      stdout, _stderr, status = run_scan(dir)
      assert_equal 1, status.exitstatus
      assert_match(/high_entropy/, stdout)
    end
  end

  def test_detects_pem_private_key_marker
    with_repo do |dir|
      pem = <<~PEM
        -----BEGIN PRIVATE KEY-----
        ABCDEF123456
        -----END PRIVATE KEY-----
      PEM
      File.write(File.join(dir, "key.pem"), pem)
      system({"HOME" => dir}, "git", "add", "key.pem", chdir: dir)
      stdout, _stderr, status = run_scan(dir)
      assert_equal 1, status.exitstatus
      assert_match(/pem_private_key/, stdout)
    end
  end
end
