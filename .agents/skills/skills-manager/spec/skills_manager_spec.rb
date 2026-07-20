# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'yaml'

require_relative '../lib/skills_manager'

class SkillsManagerTest < Minitest::Test
  def with_manager(extra_skills = {})
    Dir.mktmpdir do |dir|
      root = File.join(dir, 'dots')
      external_root = File.join(root, '.ai', 'external-skills')
      FileUtils.mkdir_p(external_root)
      manifest = {
        'auditors' => {
          'skillspector' => auditor('skillspector'),
          'cisco-skill-scanner' => auditor('cisco_skill_scanner'),
          'sentry-skill-scanner' => auditor('sentry_skill_scanner').merge('source_path' => 'skills/skill-scanner')
        },
        'skills' => {
          'normal-skill' => {
            'origin' => 'https://example.test/normal.git',
            'ref' => 'main'
          }
        }.merge(extra_skills)
      }
      manifest_path = File.join(external_root, 'external-skills.yml')
      File.write(manifest_path, YAML.dump(manifest))
      yield SkillsManager::Manager.new(repo_root: root, external_root: external_root, manifest_path: manifest_path)
    end
  end

  def auditor(adapter)
    {
      'origin' => "https://example.test/#{adapter}.git",
      'ref' => 'main',
      'adapter' => adapter
    }
  end

  def test_normal_skill_is_audited_by_all_three_auditors
    with_manager do |manager|
      assert_equal %w[skillspector cisco-skill-scanner sentry-skill-scanner], manager.audit_plan('normal-skill')
    end
  end

  def test_auditor_update_has_no_audit_plan
    with_manager do |manager|
      assert_empty manager.audit_plan('skillspector')
    end
  end

  def test_auditor_audit_is_refused
    with_manager do |manager|
      error = assert_raises(SkillsManager::Error) { manager.audit('skillspector') }
      assert_match(/auditor skills are not audited/, error.message)
    end
  end

  def test_sentry_source_path_uses_flat_target
    with_manager do |manager|
      output = capture_io { manager.list('sentry-skill-scanner') }.first
      assert_includes output, '/.ai/external-skills/sentry-skill-scanner'
      refute_includes output, '/.ai/external-skills/.repos/sentry-skill-scanner'
    end
  end

  def test_checkout_path_must_stay_under_external_root
    bad_skill = {
      'bad-skill' => {
        'origin' => 'https://example.test/bad.git',
        'ref' => 'main',
        'checkout' => '../bad'
      }
    }

    with_manager(bad_skill) do |manager|
      error = nil
      capture_io do
        error = assert_raises(SkillsManager::Error) { manager.list('bad-skill') }
      end
      assert_match(/checkout path must stay under/, error.message)
    end
  end

end
