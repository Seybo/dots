# frozen_string_literal: true

require "minitest/autorun"
require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "shellwords"
require "tmpdir"

class DotsBackupSpec < Minitest::Test
  SCRIPT = File.expand_path("../scripts/dots_backup.rb", __dir__)

  def run_report(inventory_path, *args, chdir: Dir.pwd)
    Open3.capture3(SCRIPT, "--inventory", inventory_path, *args, chdir: chdir)
  end

  def write_inventory(content)
    dir = Dir.mktmpdir("dots-backup-")
    path = File.join(dir, "inventory.yml")
    File.write(path, content)
    [dir, path]
  end

  def test_renders_unknown_values_without_guessing
    dir, path = write_inventory(<<~YAML)
      version: 1
      active_backups:
        - name: Dropbox
          tool: dropbox
          included:
            - ~/Dropbox
    YAML

    stdout, stderr, status = run_report(path)

    assert_equal 0, status.exitstatus, stderr
    assert_match(/Dropbox/, stdout)
    assert_match(/included folders:/, stdout)
    assert_match(%r{~/Dropbox}, stdout)
    assert_match(/excluded folders: unknown/, stdout)
    assert_match(/last run: unknown/, stdout)
    assert_match(/status: unknown/, stdout)
  ensure
    FileUtils.remove_entry(dir) if dir && Dir.exist?(dir)
  end

  def test_renders_active_backup_entry_details
    dir, path = write_inventory(<<~YAML)
      version: 1
      active_backups:
        - name: Rclone higr
          tool: rclone
          included:
            - /Volumes/vault/higr
          excluded:
            - /Volumes/vault/higr/cache
          last_run: "2026-07-18 10:00:00"
          status: success
    YAML

    stdout, stderr, status = run_report(path)

    assert_equal 0, status.exitstatus, stderr
    assert_match(/Rclone higr \(rclone\)/, stdout)
    assert_match(%r{/Volumes/vault/higr}, stdout)
    assert_match(%r{/Volumes/vault/higr/cache}, stdout)
    assert_match(/last run: 2026-07-18 10:00:00/, stdout)
    assert_match(/status: success/, stdout)
  ensure
    FileUtils.remove_entry(dir) if dir && Dir.exist?(dir)
  end

  def test_detects_overlapping_included_paths_across_destinations
    dir, path = write_inventory(<<~YAML)
      version: 1
      active_backups:
        - name: Dropbox
          tool: dropbox
          included:
            - /tmp/dots-backup/Documents
          excluded: []
        - name: Time Machine
          tool: time_machine
          included:
            - /tmp/dots-backup/Documents/Taxes
          excluded: []
    YAML

    stdout, stderr, status = run_report(path)

    assert_equal 1, status.exitstatus, stderr
    assert_match(/Overlap findings:/, stdout)
    assert_match(%r{Dropbox covers /tmp/dots-backup/Documents}, stdout)
    assert_match(%r{Time Machine covers /tmp/dots-backup/Documents/Taxes}, stdout)
  ensure
    FileUtils.remove_entry(dir) if dir && Dir.exist?(dir)
  end

  def test_excluded_paths_reduce_overlap_checks
    dir, path = write_inventory(<<~YAML)
      version: 1
      active_backups:
        - name: Dropbox
          tool: dropbox
          included:
            - /tmp/dots-backup/Documents
          excluded:
            - /tmp/dots-backup/Documents/Taxes
        - name: Time Machine
          tool: time_machine
          included:
            - /tmp/dots-backup/Documents/Taxes
          excluded: []
    YAML

    stdout, stderr, status = run_report(path)

    assert_equal 0, status.exitstatus, stderr
    refute_match(/Overlap findings:/, stdout)
  ensure
    FileUtils.remove_entry(dir) if dir && Dir.exist?(dir)
  end

  def test_non_path_included_values_are_not_overlap_checked
    dir, path = write_inventory(<<~YAML)
      version: 1
      active_backups:
        - name: dots
          tool: rsync
          included:
            - /Users/inseybo/.dots
          excluded: []
        - name: Time Machine
          tool: time_machine
          included:
            - configured eligible volumes minus exclusions
          excluded: []
    YAML

    stdout, stderr, status = run_report(path)

    assert_equal 0, status.exitstatus, stderr
    refute_match(/Overlap findings:/, stdout)
  ensure
    FileUtils.remove_entry(dir) if dir && Dir.exist?(dir)
  end

  def test_report_shows_mounted_status_from_inventory_volume_path
    dir, path = write_inventory(<<~YAML)
      version: 1
      active_backups:
        - name: Extreme
          tool: external_drive
          volume_path: #{Dir.tmpdir}
          included:
            - #{Dir.tmpdir}/backups
          excluded: []
    YAML

    stdout, stderr, status = run_report(path)

    assert_equal 0, status.exitstatus, stderr
    assert_match(/Extreme \(external_drive\)/, stdout)
    assert_match(/mounted: yes/, stdout)
  ensure
    FileUtils.remove_entry(dir) if dir && Dir.exist?(dir)
  end

  def test_script_resolves_default_inventory_outside_repo_cwd
    stdout, stderr, status = Open3.capture3(SCRIPT, chdir: Dir.tmpdir)

    assert_includes [0, 1], status.exitstatus, stderr
    assert_match(/Dots Backup Report/, stdout)
  end

  def test_run_mode_requires_supported_run_type
    dir = Dir.mktmpdir("dots-backup-run-")
    inventory_path = inventory_with_command(dir, "higr", "backup", "echo backup")

    _stdout, stderr, status = Open3.capture3(SCRIPT, "--inventory", inventory_path, "--run", "higr", "--type", "restore")

    assert_equal 2, status.exitstatus
    assert_match(/supported run types are dry-run, backup, check/, stderr)
  ensure
    FileUtils.remove_entry(dir) if dir && Dir.exist?(dir)
  end

  def test_run_mode_prints_command_and_does_not_execute_without_confirmation
    dir = Dir.mktmpdir("dots-backup-run-")
    marker_path = File.join(dir, "marker")
    status_dir = File.join(dir, "status")
    command = ruby_command(%Q{File.write(#{marker_path.inspect}, "ran")})
    inventory_path = inventory_with_command(dir, "higr", "dry-run", command)

    stdout, stderr, status = Open3.capture3(
      SCRIPT,
      "--inventory", inventory_path,
      "--status-dir", status_dir,
      "--run", "higr",
      "--type", "dry-run",
      stdin_data: "no\n"
    )

    assert_equal 1, status.exitstatus, stderr
    assert_match(/Command: #{Regexp.escape(command)}/, stdout)
    assert_match(/Run cancelled/, stdout)
    refute File.exist?(marker_path)
    refute Dir.exist?(status_dir)
  ensure
    FileUtils.remove_entry(dir) if dir && Dir.exist?(dir)
  end

  def test_run_mode_executes_confirmed_command_and_writes_status
    dir = Dir.mktmpdir("dots-backup-run-")
    marker_path = File.join(dir, "marker")
    status_dir = File.join(dir, "status")
    command = ruby_command(%Q{File.write(#{marker_path.inspect}, "ran"); puts "run-ok"})
    inventory_path = inventory_with_command(dir, "higr", "dry-run", command)

    stdout, stderr, status = Open3.capture3(
      SCRIPT,
      "--inventory", inventory_path,
      "--status-dir", status_dir,
      "--run", "higr",
      "--type", "dry-run",
      stdin_data: "yes\n"
    )
    status_payload = JSON.parse(File.read(File.join(status_dir, "higr-dry-run.json")))

    assert_equal 0, status.exitstatus, stderr
    assert_match(/Command: #{Regexp.escape(command)}/, stdout)
    assert_equal "ran", File.read(marker_path)
    assert_equal "higr", status_payload.fetch("name")
    assert_equal "dry-run", status_payload.fetch("run_type")
    assert_equal command, status_payload.fetch("command")
    assert_equal 0, status_payload.fetch("exit_status")
    assert_equal "success", status_payload.fetch("status")
    assert_match(/run-ok/, File.read(status_payload.fetch("stdout_log")))
  ensure
    FileUtils.remove_entry(dir) if dir && Dir.exist?(dir)
  end

  def test_report_uses_skill_managed_status_files_for_last_run_and_status
    dir = Dir.mktmpdir("dots-backup-run-")
    status_dir = File.join(dir, "status")
    FileUtils.mkdir_p(status_dir)
    inventory_path = inventory_with_command(dir, "higr", "backup", "echo backup")
    File.write(File.join(status_dir, "higr-backup.json"), JSON.dump({
      "name" => "higr",
      "run_type" => "backup",
      "command" => "echo backup",
      "finished_at" => "2026-07-18T10:00:00Z",
      "exit_status" => 0,
      "status" => "success"
    }))

    stdout, stderr, status = run_report(inventory_path, "--status-dir", status_dir)

    assert_equal 0, status.exitstatus, stderr
    assert_match(/last run: 2026-07-18T10:00:00Z/, stdout)
    assert_match(/status: success/, stdout)
  ensure
    FileUtils.remove_entry(dir) if dir && Dir.exist?(dir)
  end

  private

  def ruby_command(code)
    "#{RbConfig.ruby.shellescape} -e #{code.shellescape}"
  end

  def inventory_with_command(dir, name, run_type, command)
    inventory_path = File.join(dir, "inventory.yml")
    File.write(inventory_path, <<~YAML)
      version: 1
      active_backups:
        - name: #{name}
          tool: rsync
          included:
            - /tmp/#{name}
          excluded: []
          commands:
            #{run_type}: #{command.inspect}
    YAML
    inventory_path
  end
end
