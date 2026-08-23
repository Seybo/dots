# frozen_string_literal: true

require "fileutils"
require "json"
require "minitest/autorun"
require "tmpdir"

require_relative "../scripts/handit"

class HanditSpec < Minitest::Test
  def setup
    @root = Dir.mktmpdir("handit-")
    @tasks_root = File.join(@root, "tasks")
    @cloud_root = File.join(@root, "cloud")
    @task_path = File.join(@tasks_root, "env", "0042-mobile-pi-session-handoff")
    @session_path = File.join(@root, "session.jsonl")
    @summary_path = File.join(@root, "summary.md")
    @session_id = "session-123"
    @scanner_path = File.join(@root, "scanner")

    FileUtils.mkdir_p(@task_path)
    File.write(File.join(@task_path, "task.md"), "# Context\n")
    File.write(@summary_path, "We chose the smallest working design.\n")
    write_session
    write_scanner
  end

  def teardown
    FileUtils.remove_entry(@root) if File.exist?(@root)
  end

  def test_pass_publishes_bundle_and_receive_cleans_it_after_validation
    destination = runner.pass(@task_path, @summary_path)

    assert_equal handoff_path, destination
    assert_equal %w[HANDOFF.md TRANSIT.md session.jsonl], Dir.children(destination).sort
    assert_equal File.binread(@session_path), File.binread(File.join(destination, "session.jsonl"))
    assert_includes File.read(File.join(destination, "HANDOFF.md")), "We chose the smallest working design."
    assert_includes File.read(File.join(destination, "HANDOFF.md")), "repository is unavailable"

    transit_path = File.join(destination, "TRANSIT.md")
    File.write(transit_path, "Choose option B.\n")
    assert_equal transit_path, runner.receive(@task_path)

    runner.complete(@task_path)
    refute File.exist?(destination)
  end

  def test_pass_blocks_sensitive_content_without_publishing
    write_session("BLOCK_ME")

    error = assert_raises(Handit::SensitiveContentError) do
      runner.pass(@task_path, @summary_path)
    end

    assert_includes error.message, "<redacted>"
    refute File.exist?(handoff_path)
  end

  def test_pass_allows_sensitive_content_only_with_explicit_override
    write_session("BLOCK_ME")

    destination = runner.pass(@task_path, @summary_path, is_sensitive_allowed: true)

    assert_equal handoff_path, destination
    assert File.file?(File.join(destination, "session.jsonl"))
  end

  def test_receive_rejects_a_different_pi_session
    runner.pass(@task_path, @summary_path)
    File.write(File.join(handoff_path, "TRANSIT.md"), "Decision\n")

    mismatched_runner = build_runner(session_id: "another-session")
    error = assert_raises(Handit::Error) { mismatched_runner.receive(@task_path) }

    assert_match(/original Pi session/, error.message)
  end

  def test_receive_rejects_the_unchanged_transit_template
    runner.pass(@task_path, @summary_path)

    error = assert_raises(Handit::Error) { runner.receive(@task_path) }

    assert_match(/TRANSIT\.md is empty/, error.message)
  end

  def test_pass_does_not_replace_an_existing_handoff
    runner.pass(@task_path, @summary_path)

    error = assert_raises(Handit::Error) { runner.pass(@task_path, @summary_path) }

    assert_match(/already exists/, error.message)
  end

  def test_pass_removes_a_temporary_summary_after_use
    runner.pass(@task_path, @summary_path, is_summary_temporary: true)

    refute File.exist?(@summary_path)
  end

  def test_tasks_root_uses_dev_root
    dev_root = File.join(@root, "dev")

    assert_equal File.join(dev_root, "_tasks"), Handit.tasks_root("DEV_ROOT" => dev_root)
  end

  private

  def runner
    @runner ||= build_runner
  end

  def build_runner(session_id: @session_id)
    Handit::Runner.new(
      tasks_root: @tasks_root,
      cloud_root: @cloud_root,
      scanner_path: @scanner_path,
      session_file: @session_path,
      session_id: session_id
    )
  end

  def handoff_path
    File.join(@cloud_root, "env", "0042-mobile-pi-session-handoff", "handoff")
  end

  def write_session(text = "safe")
    entries = [
      { type: "session", version: 3, id: @session_id, timestamp: "2026-01-01T00:00:00Z", cwd: "/repo" },
      {
        type: "message",
        id: "12345678",
        parentId: nil,
        timestamp: "2026-01-01T00:00:01Z",
        message: { role: "user", content: text, timestamp: 1 }
      }
    ]
    File.write(@session_path, entries.map(&:to_json).join("\n") + "\n")
  end

  def write_scanner
    File.write(
      @scanner_path,
      <<~RUBY
        #!/usr/bin/env ruby
        path = ARGV.fetch(1)
        if File.read(path).include?("BLOCK_ME")
          puts "Findings: test <redacted>"
          exit 1
        end
        puts "No findings"
      RUBY
    )
    FileUtils.chmod(0o755, @scanner_path)
  end
end
