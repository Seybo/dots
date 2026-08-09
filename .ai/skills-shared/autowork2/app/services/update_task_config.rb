# frozen_string_literal: true

require 'fileutils'
require 'json'

class UpdateTaskConfig
  include ServiceObject

  arguments :task_path, :active_base_ref, :active_base_commit_sha

  def call
    validate_value(active_base_ref, 'Active base ref')
    validate_value(active_base_commit_sha, 'Active base commit SHA')
    write(updated_data)
    updated_data
  end

  private

  def updated_data
    @updated_data ||= config.merge(
      'branch' => branch.merge(
        'active_base_ref' => active_base_ref,
        'active_base_commit_sha' => active_base_commit_sha
      )
    )
  end

  def config
    @config ||= ReadTaskConfig.call(task_path: task_path)
  end

  def branch
    config.fetch('branch')
  end

  def validate_value(value, label)
    return if value.is_a?(String) && !value.strip.empty?

    raise "#{label} must be a non-empty string"
  end

  def write(value)
    temporary_path = "#{config_path}.tmp-#{Process.pid}-#{object_id}"
    File.write(temporary_path, "#{JSON.pretty_generate(value)}\n", mode: 'wx')
    File.rename(temporary_path, config_path)
  ensure
    FileUtils.rm_f(temporary_path) unless temporary_path.nil?
  end

  def config_path
    @config_path ||= File.join(File.realpath(task_path), 'config.json')
  end
end
