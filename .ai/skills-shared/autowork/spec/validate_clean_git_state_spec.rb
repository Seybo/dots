# frozen_string_literal: true

require 'open3'
require 'tmpdir'
require_relative 'spec_helper'

RSpec.describe ValidateCleanGitState do
  let(:project_path) { Dir.mktmpdir('validate-clean-git-state-spec') }

  before do
    git!('init', '-q', '--initial-branch=main')
    git!('config', 'user.email', 'autowork@example.com')
    git!('config', 'user.name', 'Autowork')
    File.write(File.join(project_path, 'tracked.txt'), "initial\n")
    git!('add', 'tracked.txt')
    git!('commit', '-q', '-m', 'Initial commit')
  end

  after do
    FileUtils.remove_entry(project_path)
  end

  it 'returns the full current HEAD for a clean working tree' do
    expect(described_class.call(project_path: project_path)).to eq(git!('rev-parse', 'HEAD').strip)
  end

  it 'rejects a dirty working tree' do
    File.write(File.join(project_path, 'tracked.txt'), "changed\n")

    expect { described_class.call(project_path: project_path) }.
      to raise_error(/Working tree is not clean/)
  end

  it 'surfaces failure when HEAD does not exist' do
    empty_project_path = Dir.mktmpdir('validate-clean-git-state-empty-spec')
    git!('init', '-q', '--initial-branch=main', path: empty_project_path)

    expect { described_class.call(project_path: empty_project_path) }.
      to raise_error(/git -C .* rev-parse HEAD failed/)
  ensure
    FileUtils.remove_entry(empty_project_path)
  end

  def git!(*arguments, path: project_path)
    stdout, stderr, status = Open3.capture3('git', '-C', path, *arguments)
    raise stderr unless status.success?

    stdout
  end
end
