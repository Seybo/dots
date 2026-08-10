# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe 'Task workflow config contract' do
  let(:taskit) { File.read(File.expand_path('../../taskit/SKILL.md', __dir__)) }
  let(:workit) { File.read(File.expand_path('../../workit/SKILL.md', __dir__)) }
  let(:resolution) { File.read(File.expand_path('../../components/task-resolution.md', __dir__)) }
  let(:branch_config) { File.read(File.expand_path('../../components/task-branch-config.md', __dir__)) }

  it 'makes one shared component authoritative for Taskit and Workit' do
    expect(taskit).to include('../components/task-branch-config.md')
    expect(workit).to include('../components/task-branch-config.md')
    expect(resolution).to include('task-branch-config.md')
    expect(taskit).not_to include('original_base_ref')
    expect(workit).not_to include('original_base_ref')
  end

  it 'defines complete branch config and immutable original fields' do
    %w[
      name
      original_base_ref
      original_base_commit_sha
      active_base_ref
      active_base_commit_sha
    ].each { |key| expect(branch_config).to include(%("#{key}")) }
    expect(branch_config).to match(/Original base fields.*never change/im)
    expect(branch_config).to match(/Preserve unrelated top-level sections/im)
  end

  it 'defines explicit, implicit, and existing Shortcut branch setup once' do
    expect(branch_config).to include('checkout --no-track -b <branch-name> <base-ref>')
    expect(branch_config).to match(/configured upstream.*same SHA/im)
    expect(branch_config).to match(/otherwise select the exact local source branch/im)
    expect(branch_config).to match(/config is missing or incomplete.*explicit `--base <ref>`/im)
    expect(branch_config).to match(/Do not infer.*merge-base.*reflog/im)
  end

  it 'assigns local config initialization to Workit without local rebasing' do
    expect(branch_config).to match(/Taskit.*does not record local Git\s+metadata/im)
    expect(branch_config).to match(/Workit.*immediately before planning.*Autoimplement/im)
    expect(branch_config).to match(/Local Tasks never.*rebase/im)
    expect(workit).to include('**Local Task setup**')
  end
end
