# frozen_string_literal: true

require 'json'

class ReadTaskConfig
  include ServiceObject

  BRANCH_KEYS = %w[
    name
    original_base_ref
    original_base_commit_sha
    active_base_ref
    active_base_commit_sha
  ].freeze

  arguments :task_path

  def call
    validate_data
    validate_branch
    data
  end

  private

  def validate_data
    raise 'Task config must contain a JSON object' unless data.is_a?(Hash)
  end

  def validate_branch
    raise 'Task branch config must contain a JSON object' unless branch.is_a?(Hash)

    BRANCH_KEYS.each do |key|
      value = branch.fetch(key) { raise "Missing Task branch config: #{key}" }
      next if value.is_a?(String) && !value.strip.empty?

      raise "Task branch config #{key} must be a non-empty string"
    end
  end

  def data
    @data ||= begin
      raise "Missing Task config: #{config_path}" unless File.file?(config_path)

      JSON.parse(File.read(config_path))
    end
  end

  def branch
    data.fetch('branch') { raise 'Missing Task branch config: branch' }
  end

  def config_path
    @config_path ||= File.join(File.realpath(task_path), 'config.json')
  end
end
