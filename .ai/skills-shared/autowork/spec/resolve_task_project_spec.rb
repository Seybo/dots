# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'
require_relative 'spec_helper'

RSpec.describe ResolveTaskProject do
  let(:root_path) { Dir.mktmpdir('resolve-task-project-spec') }
  let(:projects_file) { File.join(root_path, 'projects.yml') }
  let(:stow_dir) { File.join(root_path, 'dots') }
  let(:dev_root) { File.join(root_path, 'dev') }

  before do
    stub_const('ResolveTaskProject::PROJECTS_FILE', projects_file)
    stub_const('ResolveTaskProject::DEV_ROOT', dev_root)
    stub_const('ResolveTaskProject::STOW_DIR', stow_dir)
    FileUtils.mkdir_p(File.join(stow_dir, '_tasks', '0001-env-task'))
    FileUtils.mkdir_p(File.join(dev_root, 'projects/shaka/trp/_tasks/0002-trp-task'))
    File.write(projects_file, <<~YAML)
      version: 2
      projects:
        env:
          checkout_layout: direct
          checkout_path: $STOW_DIR
        shaka_trp:
          checkout_layout: ordinal_workspaces
          code_root: projects/shaka/trp
    YAML
  end

  after do
    FileUtils.remove_entry(root_path)
  end

  it 'resolves a direct project from its registered task root' do
    task_path = File.join(stow_dir, '_tasks', '0001-env-task')

    expect(described_class.call(task_path: task_path)).to eq('env')
  end

  it 'resolves an ordinal project from its registered code root' do
    task_path = File.join(dev_root, 'projects/shaka/trp/_tasks/0002-trp-task')

    expect(described_class.call(task_path: task_path)).to eq('shaka_trp')
  end

  it 'rejects a task outside registered task roots' do
    task_path = File.join(root_path, 'unknown', '_tasks', '0003-unknown')
    FileUtils.mkdir_p(task_path)

    expect { described_class.call(task_path: task_path) }.
      to raise_error(/not under a registered project task root/)
  end
end
