# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'json'
require 'open3'
require 'tmpdir'

class ReviewFactory
  class << self
    def call(**attributes)
      project_path = attributes.fetch(:project_path)
      branch_name = attributes.fetch(:branch_name)
      base_ref = attributes.fetch(:base_ref)
      base_commit_sha = attributes.fetch(:base_commit_sha)
      task = task_for(project_path, branch_name, base_commit_sha, base_ref, base_commit_sha)
      StoreReview.call(
        task_context: {
          task: task,
          config: config(branch_name, base_ref, base_commit_sha)
        },
        source: attributes.fetch(:source),
        starting_commit_sha: head_sha(project_path) || base_commit_sha,
        issue_data: attributes.fetch(:issue_data)
      )
    end

    def insert(**attributes)
      project_path = attributes.fetch(:project_path)
      branch_name = attributes.fetch(:branch_name)
      starting_commit_sha = attributes.fetch(:starting_commit_sha)
      base_ref = attributes.fetch(:base_ref)
      base_commit_sha = attributes.fetch(:base_commit_sha)
      task = task_for(project_path, branch_name, starting_commit_sha, base_ref, base_commit_sha)
      Database.connection[:reviews].insert(
        created_at: Time.now,
        completed_at: attributes[:completed_at],
        number: attributes.fetch(:number, 1),
        source: attributes.fetch(:source, 'local'),
        starting_commit_sha: starting_commit_sha,
        state: attributes.fetch(:state),
        task_id: task.fetch(:id)
      )
    end

    private

    def task_for(project_path, branch_name, starting_commit_sha, base_ref, base_commit_sha)
      tasks = Database.connection[:tasks]
      existing_task = tasks.where(project_path: project_path).first
      return existing_task unless existing_task.nil?

      write_task_config(project_path, branch_name, base_ref, base_commit_sha)
      tasks.where(
        id: tasks.insert(
          created_at: Time.now,
          task_path: File.realpath(task_path(project_path)),
          project_path: project_path,
          starting_commit_sha: starting_commit_sha,
          state: 'final_checks_passed',
          super_review_agent: 'claude'
        )
      ).first
    end

    def write_task_config(project_path, branch_name, base_ref, base_commit_sha)
      path = task_path(project_path)
      FileUtils.mkdir_p(path)
      config_path = File.join(path, 'config.json')
      File.write(config_path, JSON.pretty_generate(config(branch_name, base_ref, base_commit_sha)))
    end

    def task_path(project_path)
      File.join(Dir.tmpdir, 'autowork-spec-tasks', Digest::SHA256.hexdigest(project_path))
    end

    def config(branch_name, base_ref, base_commit_sha)
      {
        'branch' => {
          'name' => branch_name,
          'original_base_ref' => base_ref,
          'original_base_commit_sha' => base_commit_sha,
          'active_base_ref' => base_ref,
          'active_base_commit_sha' => base_commit_sha
        }
      }
    end

    def head_sha(project_path)
      return unless File.directory?(project_path)

      stdout, _stderr, status = Open3.capture3('git', '-C', project_path, 'rev-parse', 'HEAD')
      stdout.strip if status.success?
    end
  end
end
