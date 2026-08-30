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
      token = ["ghp_", "1234567890abcdef", "12345678"].join
      File.write(File.join(dir, "tok.txt"), token)
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
      token = ["ghp_", "1234567890abcdef", "12345678"].join
      File.write(unstaged_path, "#{token}\n")

      stdout, _stderr, status = run_scan(dir)
      assert_equal 0, status.exitstatus
      assert_match(/Checking files \(1\):/, stdout)
      assert_match(/staged\.txt/, stdout)
      refute_match(/unstaged\.txt/, stdout)
      refute_match(/github_token/, stdout)
    end
  end

  def test_unstaged_option_scans_unstaged_changes_even_when_staged_changes_exist
    with_repo do |dir|
      index_path = File.join(dir, "index_only.txt")
      unstaged_path = File.join(dir, "unstaged.txt")

      File.write(index_path, "safe staged change\n")
      system({"HOME" => dir}, "git", "add", "index_only.txt", chdir: dir)
      File.write(unstaged_path, "safe\n")
      system({"HOME" => dir}, "git", "add", "unstaged.txt", chdir: dir)
      system({"HOME" => dir}, "git", "commit", "-m", "init", chdir: dir)

      File.write(index_path, "safe staged update\n")
      system({"HOME" => dir}, "git", "add", "index_only.txt", chdir: dir)
      token = ["ghp_", "1234567890abcdef", "12345678"].join
      File.write(unstaged_path, "#{token}\n")

      stdout, _stderr, status = run_scan(dir, "--unstaged")
      assert_equal 1, status.exitstatus
      assert_match(/Checking files \(1\):/, stdout)
      assert_match(/unstaged\.txt/, stdout)
      refute_match(/index_only\.txt/, stdout)
      assert_match(/github_token/, stdout)
    end
  end

  def test_only_changed_lines_are_scanned_by_default
    with_repo do |dir|
      path = File.join(dir, "config.txt")
      token = ["ghp_", "999999999999", "999999999999"].join
      File.write(path, "token #{token}\n")
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
      token = ["ghp_", "aaaaaaaaaaaa", "aaaaaaaaaaaa"].join
      File.write(path, "token #{token}\n")
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

      token = ["ghp_", "changedtoken", "12345678901234"].join
      File.write(path, "now token #{token}\n")

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

  def test_detects_real_ssh_destination_ip
    with_repo do |dir|
      destination = ["alice@", "8.8.", "8.8"].join
      File.write(File.join(dir, "ssh.rb"), "DESTINATION = '#{destination}'\n")
      system({"HOME" => dir}, "git", "add", "ssh.rb", chdir: dir)

      stdout, _stderr, status = run_scan(dir)
      assert_equal 1, status.exitstatus
      assert_match(/ssh_destination_ip/, stdout)
      assert_match(/<redacted>/, stdout)
      refute_includes stdout, destination
    end
  end

  def test_detects_bare_tailscale_ipv4_address
    with_repo do |dir|
      address = ["100.105.", "225.127"].join
      File.write(File.join(dir, "host.rb"), "OMA_IP = '#{address}'\n")
      system({"HOME" => dir}, "git", "add", "host.rb", chdir: dir)

      stdout, _stderr, status = run_scan(dir)
      assert_equal 1, status.exitstatus
      assert_match(/tailscale_ipv4/, stdout)
      assert_match(/<redacted>/, stdout)
      refute_includes stdout, address
    end
  end

  def test_detects_tailscale_ipv6_address
    with_repo do |dir|
      address = ["fd7a:115c:", "a1e0::1234:5678"].join
      File.write(File.join(dir, "host.txt"), "HostName #{address}\n")
      system({"HOME" => dir}, "git", "add", "host.txt", chdir: dir)

      stdout, _stderr, status = run_scan(dir)
      assert_equal 1, status.exitstatus
      assert_match(/tailscale_ipv6/, stdout)
      assert_match(/<redacted>/, stdout)
      refute_includes stdout, address
    end
  end

  def test_allows_ipv4_addresses_outside_tailscale_cgnat_range
    with_repo do |dir|
      File.write(File.join(dir, "hosts.txt"), "100.63.255.255\n100.128.0.1\n")
      system({"HOME" => dir}, "git", "add", "hosts.txt", chdir: dir)

      stdout, _stderr, status = run_scan(dir)
      assert_equal 0, status.exitstatus
      assert_match(/No findings/, stdout)
      refute_match(/tailscale_ipv4/, stdout)
    end
  end

  def test_allows_documentation_and_loopback_ssh_destination_ips
    with_repo do |dir|
      destinations = [
        "dev@192.0.2.10",
        "dev@198.51.100.10",
        "dev@203.0.113.10",
        "dev@127.0.0.1"
      ]
      File.write(File.join(dir, "ssh.txt"), destinations.join("\n"))
      system({"HOME" => dir}, "git", "add", "ssh.txt", chdir: dir)

      stdout, _stderr, status = run_scan(dir)
      assert_equal 0, status.exitstatus
      assert_match(/No findings/, stdout)
      refute_match(/ssh_destination_ip/, stdout)
    end
  end

  def test_detects_aws_secret_assignment
    with_repo do |dir|
      secret = "A" * 40
      File.write(File.join(dir, "env.txt"), "AWS_SECRET_ACCESS_KEY=#{secret}\n")
      system({"HOME" => dir}, "git", "add", "env.txt", chdir: dir)
      stdout, _stderr, status = run_scan(dir)
      assert_equal 1, status.exitstatus
      assert_match(/aws_secret/, stdout)
    end
  end

  def test_does_not_flag_aws_rule_source_as_secret
    with_repo do |dir|
      source_line = "Rule.new('aws_access_key', /AKIA[0-9A-Z]{16}/),\n"
      File.write(File.join(dir, "scanner.rb"), source_line)
      system({"HOME" => dir}, "git", "add", "scanner.rb", chdir: dir)
      stdout, _stderr, status = run_scan(dir)
      assert_equal 0, status.exitstatus
      refute_match(/aws_secret/, stdout)
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
      begin_marker = ["-----BEGIN ", "PRIVATE KEY-----"].join
      end_marker = ["-----END ", "PRIVATE KEY-----"].join
      pem = <<~PEM
        #{begin_marker}
        ABCDEF123456
        #{end_marker}
      PEM
      File.write(File.join(dir, "key.pem"), pem)
      system({"HOME" => dir}, "git", "add", "key.pem", chdir: dir)
      stdout, _stderr, status = run_scan(dir)
      assert_equal 1, status.exitstatus
      assert_match(/pem_private_key/, stdout)
    end
  end

  def test_detects_encrypted_pem_private_key_marker
    with_repo do |dir|
      begin_marker = ["-----BEGIN ", "ENCRYPTED PRIVATE KEY-----"].join
      end_marker = ["-----END ", "ENCRYPTED PRIVATE KEY-----"].join
      pem = <<~PEM
        #{begin_marker}
        ABCDEF123456
        #{end_marker}
      PEM
      File.write(File.join(dir, "key.pem"), pem)
      system({"HOME" => dir}, "git", "add", "key.pem", chdir: dir)
      stdout, _stderr, status = run_scan(dir)
      assert_equal 1, status.exitstatus
      assert_match(/pem_private_key/, stdout)
    end
  end

  def test_detects_age_secret_key
    with_repo do |dir|
      key = ["AGE-SECRET-KEY-1", "q" * 58].join
      File.write(File.join(dir, "identity.txt"), key)
      system({"HOME" => dir}, "git", "add", "identity.txt", chdir: dir)
      stdout, _stderr, status = run_scan(dir)
      assert_equal 1, status.exitstatus
      assert_match(/age_secret_key/, stdout)
    end
  end

  def test_redacts_regex_secret_values_in_output
    with_repo do |dir|
      token = ["ghp_", "1234567890abcdef", "12345678"].join
      File.write(File.join(dir, "tok.txt"), "token #{token}\n")
      system({"HOME" => dir}, "git", "add", "tok.txt", chdir: dir)
      stdout, _stderr, status = run_scan(dir)
      assert_equal 1, status.exitstatus
      assert_match(/github_token/, stdout)
      assert_match(/<redacted>/, stdout)
      refute_includes stdout, token
    end
  end

  def test_redacts_absolute_user_paths_in_snippets
    with_repo do |dir|
      token = ["ghp_", "1234567890abcdef", "12345678"].join
      File.write(File.join(dir, "tok.txt"), "path /Users/alice/.config token #{token}\n")
      system({"HOME" => dir}, "git", "add", "tok.txt", chdir: dir)
      stdout, _stderr, status = run_scan(dir)
      assert_equal 1, status.exitstatus
      refute_includes stdout, "/Users/alice"
      assert_includes stdout, "/Users/<redacted>"
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

  def test_file_option_scans_an_arbitrary_file_outside_git
    Dir.mktmpdir("dots-check-file-") do |dir|
      token = ["ghp_", "1234567890abcdef", "12345678"].join
      path = File.join(dir, "session.jsonl")
      File.write(path, "token #{token}\n")

      stdout, _stderr, status = run_scan(dir, "--file", path)
      assert_equal 1, status.exitstatus
      assert_match(/github_token/, stdout)
      refute_includes stdout, token
    end
  end

  def test_file_option_scans_files_larger_than_the_git_target_limit
    Dir.mktmpdir("dots-check-file-") do |dir|
      token = ["ghp_", "1234567890abcdef", "12345678"].join
      path = File.join(dir, "large-session.jsonl")
      File.write(path, "safe line\n" * 110_000)
      File.open(path, "a") { |file| file.puts "token #{token}" }

      stdout, stderr, status = run_scan(dir, "--file", path)
      assert_equal 1, status.exitstatus
      assert_match(/github_token/, stdout)
      refute_match(/Skipping/, stderr)
    end
  end

  def test_file_option_rejects_git_target_options
    Dir.mktmpdir("dots-check-file-") do |dir|
      path = File.join(dir, "session.jsonl")
      File.write(path, "safe\n")

      _stdout, stderr, status = run_scan(dir, "--file", path, "--all")
      assert_equal 2, status.exitstatus
      assert_match(/--file cannot be combined/, stderr)
    end
  end
end
