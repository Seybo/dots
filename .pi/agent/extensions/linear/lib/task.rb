# frozen_string_literal: true

require_relative 'client'
require_relative 'markdown'
require_relative 'registry'

module Linear
  class Task
    def initialize(client: Client.new, registry: Registry.new)
      @client = client
      @registry = registry
    end

    def import(project, selector)
      destination = @client.discover(@registry.config(project))
      issue = @client.get_issue(selector)
      verify_team(issue, destination)
      root = existing_root(project)
      ensure_no_task(root, issue.fetch('identifier'))
      folder = File.join(root, folder_name(issue))
      Dir.mkdir(folder)
      text = "# Story details\n\nName: #{issue.fetch('title')}\n\n# Context\n\n#{issue['description']}"
      File.write(File.join(folder, 'task.md'), text)
      save_identity(folder, {}, issue)
      handoff(issue, folder)
    end

    def convert(project, path, type, assignee_id: nil)
      config = @registry.config(project)
      root = existing_root(project)
      path = source_path(root, path)
      folder = File.dirname(path)
      metadata = load_config(folder)
      if metadata['linear']
        raise Error, "Task already associated with #{metadata.fetch('linear').fetch('identifier')}; do not recreate it"
      end

      params = Markdown.parse(File.read(path))
      raise Error, 'Draft requires Name: in # Story details' unless params['title']
      raise Error, "type must be #{Client::TYPES.join(', ')}" unless Client::TYPES.include?(type)

      slug(params.fetch('title'))
      params['type'] = type
      params['assignee_id'] = assignee_id if assignee_id
      issue = @client.create_issue(params, @client.discover(config))
      # Persist identity first: a collision or interrupted rename must not cause another remote creation.
      save_identity(folder, metadata, issue)
      ensure_no_task(root, issue.fetch('identifier'))
      target = File.join(root, folder_name(issue))
      unless system('mv', '-n', folder, target) && !File.exist?(folder) && File.file?(File.join(target, 'task.md'))
        raise Error, 'No-clobber task rename failed'
      end

      handoff(issue, target)
    rescue Error, SystemCallError => error
      raise unless issue

      raise Error, "Created #{issue.fetch('identifier')} #{issue.fetch('url')}, but local preparation failed: " \
                   "#{error.message}. Do not recreate this issue."
    end

    def update(selector, path = nil)
      identifier = @client.identifier(selector)
      path ||= @registry.task_path(identifier)
      path = File.expand_path(path)
      params = Markdown.parse(File.read(path))
      issue = @client.get_issue(selector)
      if File.basename(path) == 'task.md'
        metadata = load_config(File.dirname(path))['linear']
        if metadata && (metadata['id'] != issue.fetch('id') || metadata['identifier'] != identifier)
          raise Error, 'Local task identity does not match the requested issue'
        end

        folder = File.basename(File.dirname(path))
        if folder.match?(/\A[A-Z][A-Z0-9]*-\d+-/) && !folder.start_with?("#{identifier}-")
          raise Error, 'Local task folder identity does not match the requested issue'
        end
      end
      @client.update_issue(issue.fetch('id'), params)
    end

    private

    def existing_root(project)
      root = @registry.task_root(project)
      raise Error, "Task root is missing: #{root}; initialize it through Taskit first" unless File.directory?(root)

      File.realpath(root)
    end

    def source_path(root, path)
      expanded = File.expand_path(path)
      unless File.file?(expanded) && File.basename(expanded) == 'task.md'
        raise Error, 'Source must be an existing task.md'
      end

      resolved = File.realpath(expanded)
      unless File.dirname(resolved, 2) == root && resolved == expanded
        raise Error, 'Source folder must be a direct child of the task root, without symlinks'
      end

      resolved
    end

    def verify_team(issue, destination)
      return if issue.fetch('team').fetch('id') == destination.fetch('team_id')

      raise Error,
            'Issue is not in the configured Linear team'
    end

    def folder_name(issue)
      "#{issue.fetch('identifier')}-#{slug(issue.fetch('title'))}"
    end

    def slug(title)
      value = title.downcase.gsub(/[^a-z0-9\s-]/, '').gsub(/\s+/, '-').gsub(/-+/, '-').sub(/\A-/, '').sub(/-\z/, '')
      raise Error, 'Issue title does not produce a usable folder slug' if value.empty?

      value
    end

    def ensure_no_task(root, identifier)
      return if Dir.glob(File.join(root, "#{identifier}-*")).empty?

      raise Error, "Local task for #{identifier} already exists"
    end

    def load_config(folder)
      path = File.join(folder, 'config.json')
      return {} unless File.exist?(path)

      config = JSON.parse(File.read(path))
      raise Error, 'config.json must be a JSON object' unless config.is_a?(Hash)

      config
    end

    def save_identity(folder, metadata, issue)
      metadata['linear'] = {
        'id' => issue.fetch('id'), 'identifier' => issue.fetch('identifier'), 'url' => issue.fetch('url'),
        'branch_name' => issue.fetch('branchName')
      }
      File.write(File.join(folder, 'config.json'), "#{JSON.pretty_generate(metadata)}\n")
    end

    def handoff(issue, folder)
      issue.merge('task_path' => File.join(folder, 'task.md'))
    end
  end
end
