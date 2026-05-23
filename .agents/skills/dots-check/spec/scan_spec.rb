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

  def test_staged_changes_take_precedence_over_unstaged_changes
    with_repo do |dir|
      staged_path = File.join(dir, "staged.txt")
      unstaged_path = File.join(dir, "unstaged.txt")

      File.write(staged_path, "safe staged change\n")
      system({"HOME" => dir}, "git", "add", "staged.txt", chdir: dir)
      File.write(unstaged_path, "ghp_1234567890abcdef12345678\n")

      stdout, _stderr, status = run_scan(dir)
      assert_equal 0, status.exitstatus
      assert_match(/Checking files \(1\):/, stdout)
      assert_match(/staged\.txt/, stdout)
      refute_match(/unstaged\.txt/, stdout)
      refute_match(/github_token/, stdout)
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

  def test_last_commits_scans_each_requested_commit
    with_repo do |dir|
      File.write(File.join(dir, "safe.txt"), "safe\n")
      system({"HOME" => dir}, "git", "add", "safe.txt", chdir: dir)
      system({"HOME" => dir}, "git", "commit", "-m", "init", chdir: dir)

      github_token = ["ghp_", "1234567890abcdef", "12345678"].join
      File.write(File.join(dir, "secret.txt"), "token #{github_token}\n")
      system({"HOME" => dir}, "git", "add", "secret.txt", chdir: dir)
      system({"HOME" => dir}, "git", "commit", "-m", "secret", chdir: dir)

      File.write(File.join(dir, "newer.txt"), "safe newer\n")
      system({"HOME" => dir}, "git", "add", "newer.txt", chdir: dir)
      system({"HOME" => dir}, "git", "commit", "-m", "newer", chdir: dir)

      stdout, _stderr, status = run_scan(dir, "--last-commits", "2")
      assert_equal 1, status.exitstatus
      assert_match(/Checking commits \(2\):/, stdout)
      assert_match(/secret\.txt/, stdout)
      assert_match(/github_token/, stdout)
    end
  end

  def test_last_commits_count_excludes_older_commits
    with_repo do |dir|
      github_token = ["ghp_", "1234567890abcdef", "12345678"].join
      File.write(File.join(dir, "secret.txt"), "token #{github_token}\n")
      system({"HOME" => dir}, "git", "add", "secret.txt", chdir: dir)
      system({"HOME" => dir}, "git", "commit", "-m", "old secret", chdir: dir)

      File.write(File.join(dir, "safe1.txt"), "safe one\n")
      system({"HOME" => dir}, "git", "add", "safe1.txt", chdir: dir)
      system({"HOME" => dir}, "git", "commit", "-m", "safe one", chdir: dir)

      File.write(File.join(dir, "safe2.txt"), "safe two\n")
      system({"HOME" => dir}, "git", "add", "safe2.txt", chdir: dir)
      system({"HOME" => dir}, "git", "commit", "-m", "safe two", chdir: dir)

      stdout, _stderr, status = run_scan(dir, "--last-commits", "2")
      assert_equal 0, status.exitstatus
      assert_match(/Checking commits \(2\):/, stdout)
      refute_match(/secret\.txt/, stdout)
      refute_match(/github_token/, stdout)
    end
  end
end
