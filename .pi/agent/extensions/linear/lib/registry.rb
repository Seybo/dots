# frozen_string_literal: true

require 'yaml'
require_relative 'client'

module Linear
  class Registry
    def initialize(path: File.expand_path('~/.ai/skills-shared/components/projects.yml'), env: ENV)
      @projects = YAML.safe_load_file(path).fetch('projects')
      @env = env
    end

    def config(project)
      entry = @projects.fetch(project) { raise Error, "Unregistered project: #{project}" }
      raise Error, "#{project} is not configured with task_provider: linear" unless entry['task_provider'] == 'linear'

      entry.fetch('linear')
    end

    def task_root(project)
      entry = @projects.fetch(project) { raise Error, "Unregistered project: #{project}" }
      root = entry.fetch(entry.fetch('checkout_layout') == 'direct' ? 'checkout_path' : 'code_root')
      root = if root == '$STOW_DIR'
               @env.fetch('STOW_DIR')
             elsif root.start_with?('/', '~')
               File.expand_path(root)
             else
               File.join(@env.fetch('DEV_ROOT'), root)
             end
      File.join(root, '_tasks')
    end

    def task_path(identifier)
      paths = @projects.keys.flat_map do |project|
        Dir.glob(File.join(task_root(project), "#{identifier}-*", 'task.md'))
      end.uniq
      raise Error, "Expected exactly one local task for #{identifier}; found #{paths.size}" unless paths.size == 1

      paths.first
    end
  end
end
