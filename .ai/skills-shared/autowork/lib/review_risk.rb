# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'time'

module Autowork
  class ReviewRiskRegistry
    VERSION = 1
    MAX_WEIGHT = 1.0

    attr_reader :path

    def initialize(project, task_root: Autowork::TASK_ROOT)
      @path = File.join(task_root, project, 'review-risk-registry.json')
    end

    def read
      return { 'version' => VERSION, 'risks' => [] } unless File.file?(path)

      data = JSON.parse(File.read(path))
      raise Error, "Review risk registry must be a JSON object: #{path}" unless data.is_a?(Hash)
      raise Error, "Review risk registry risks must be an array: #{path}" unless data['risks'].is_a?(Array)

      data
    rescue JSON::ParserError => e
      raise Error, "Invalid review risk registry #{path}: #{e.message}"
    end

    def apply!(updates, task_id:, round_id: nil)
      return if updates.empty?

      data = read
      risks = data['risks']
      updates.each do |update|
        validate_update!(update)
        existing = risks.find { |risk| risk['id'] == update['id'] }
        if existing
          merge_update!(existing, update, task_id, round_id)
        else
          risks << new_entry(update, task_id, round_id)
        end
      end
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, JSON.pretty_generate(data) + "\n")
    end

    private

    def validate_update!(update)
      raise Error, 'Review risk registry updates must be objects' unless update.is_a?(Hash)
      %w[id summary].each do |key|
        raise Error, "Review risk update #{key} must be a non-empty string" unless update[key].is_a?(String) && !update[key].strip.empty?
      end
      %w[tags triggers].each do |key|
        raise Error, "Review risk update #{key} must be an array" if update.key?(key) && !update[key].is_a?(Array)
      end
    end

    def new_entry(update, task_id, round_id)
      task_key = task_id.to_s
      round_key = round_key_for(task_key, round_id)
      {
        'id' => update['id'],
        'summary' => update['summary'],
        'tags' => Array(update['tags']).map(&:to_s).uniq,
        'triggers' => Array(update['triggers']).map(&:to_s).uniq,
        'valid_task_count' => 1,
        'valid_round_count' => 1,
        'false_positive_count' => 0,
        'weight' => weight(1, 1, 0),
        'source_tasks' => [task_key],
        'source_rounds' => [round_key],
        'last_seen_at' => Time.now.iso8601,
        'status' => 'active'
      }
    end

    def merge_update!(existing, update, task_id, round_id)
      task_key = task_id.to_s
      round_key = round_key_for(task_key, round_id)
      existing['summary'] = update['summary']
      existing['tags'] = (Array(existing['tags']) + Array(update['tags'])).map(&:to_s).uniq
      existing['triggers'] = (Array(existing['triggers']) + Array(update['triggers'])).map(&:to_s).uniq
      existing['source_tasks'] = (Array(existing['source_tasks']) + [task_key]).uniq
      existing['source_rounds'] = (Array(existing['source_rounds']) + [round_key]).uniq
      existing['valid_task_count'] = existing['source_tasks'].length
      existing['valid_round_count'] = existing['source_rounds'].length
      existing['last_seen_at'] = Time.now.iso8601
      existing['status'] = 'active'
      existing['weight'] = weight(existing['valid_task_count'], existing['valid_round_count'], existing.fetch('false_positive_count', 0))
    end

    def round_key_for(task_key, round_id)
      round_id.nil? ? task_key : "#{task_key}:#{round_id}"
    end

    def weight(task_count, round_count, false_positive_count)
      [0.25 + (task_count * 0.12) + (round_count * 0.03) - (false_positive_count * 0.1), MAX_WEIGHT].min.round(3)
    end
  end

  class ReviewRiskManifest
    def self.validate_file(path)
      data = JSON.parse(File.read(path))
      validate(data)
    rescue Errno::ENOENT
      raise Error, "Missing review risk manifest: #{path}"
    rescue JSON::ParserError => e
      raise Error, "Invalid review risk manifest #{path}: #{e.message}"
    end

    def self.validate(data)
      raise Error, 'Review risk manifest must be a JSON object' unless data.is_a?(Hash)
      raise Error, 'Review risk manifest summary must be a non-empty string' unless data['summary'].is_a?(String) && !data['summary'].strip.empty?
      unless data.key?('coverage_gaps') && data['coverage_gaps'].is_a?(Array)
        raise Error, 'Review risk manifest coverage_gaps must be a present array'
      end
      %w[registry_updates additional_findings].each do |key|
        raise Error, "Review risk manifest #{key} must be an array" if data.key?(key) && !data[key].is_a?(Array)
      end
      Array(data['registry_updates']).each { |update| validate_registry_update(update) }
      Array(data['additional_findings']).each { |finding| validate_additional_finding(finding) }
      data
    end

    def self.validate_registry_update(update)
      raise Error, 'Review risk registry updates must be objects' unless update.is_a?(Hash)
      %w[id summary].each do |key|
        raise Error, "Review risk registry update #{key} must be a non-empty string" unless update[key].is_a?(String) && !update[key].strip.empty?
      end
    end

    def self.validate_additional_finding(finding)
      raise Error, 'Review risk additional findings must be objects' unless finding.is_a?(Hash)
      %w[id severity title body].each do |key|
        raise Error, "Review risk additional finding #{key} must be a non-empty string" unless finding[key].is_a?(String) && !finding[key].strip.empty?
      end
      raise Error, 'Review risk additional finding severity must be BLOCKER or MINOR' unless %w[BLOCKER MINOR].include?(finding['severity'])
    end

    private_class_method :validate_registry_update, :validate_additional_finding
  end
end
