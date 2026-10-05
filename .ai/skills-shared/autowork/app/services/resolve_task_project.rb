# frozen_string_literal: true

require 'yaml'

class ResolveTaskProject
  include ServiceObject

  PROJECTS_FILE = File.expand_path('../../../components/projects.yml', __dir__)
  DEV_ROOT = ENV.fetch('DEV_ROOT')
  STOW_DIR = ENV.fetch('STOW_DIR')

  arguments :task_path

  def call
    project = projects.find { |_name, config| task_root(config) == canonical_task_root }
    raise "Task path is not under a registered project task root: #{task_path}" if project.nil?

    project.first
  end

  private

  def projects
    YAML.safe_load_file(PROJECTS_FILE).fetch('projects')
  end

  def task_root(config)
    File.realpath(File.join(project_root(config), '_tasks'))
  rescue Errno::ENOENT
    nil
  end

  def project_root(config)
    case config.fetch('checkout_layout')
    when 'direct'
      path = config.fetch('checkout_path').sub(%r{\A\$STOW_DIR(?=/|\z)}, STOW_DIR)
      File.expand_path(path, DEV_ROOT)
    when 'ordinal_workspaces'
      File.expand_path(config.fetch('code_root'), DEV_ROOT)
    else
      raise "Unsupported checkout layout: #{config.fetch('checkout_layout')}"
    end
  end

  def canonical_task_root
    @canonical_task_root ||= File.dirname(File.realpath(task_path))
  end
end
