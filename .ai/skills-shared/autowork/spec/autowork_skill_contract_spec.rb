# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe 'Autowork status skill contract' do
  let(:skill_path) { File.expand_path('../SKILL.md', __dir__) }
  let(:skill) { File.read(skill_path) }

  it 'defines one command-only status interface' do
    expect(skill).to include('name: autowork')
    expect(skill).to include('disable-model-invocation: true')
    expect(skill).to include('/skill:autowork --status')
    expect(skill).to include('/autowork --status [<project-or-session>] --task <task-id>')
    expect(skill).to match(%r{Reject bare `/autowork`})
    expect(skill).to match(/reject every other\s+argument\s+shape/i)
  end

  it 'uses shared project and canonical Task-folder resolution' do
    expect(skill).to include('../components/task-resolution.md')
    expect(skill).to include('`sc-<digits>`')
    expect(skill).to include('`--task <digits>`')
    expect(skill).to match(/exactly\s+one first-level Task folder/i)
    expect(skill).to include('`task.md`')
    expect(skill).to match(/Never select the newest Task folder or a SQLite row/i)
  end

  it 'passes only the shell-escaped canonical Task path to the helper' do
    expect(skill).to include(
      '/Volumes/dev/bin/skills/autoimplement show-task-status <canonical-task-path>'
    )
    expect(skill).to match(/Shell-escape the canonical Task path/)
    expect(skill).to match(/Pass no project key, Task ID, checkout, branch, or other argument/)
    expect(skill).to match(/Return helper stdout unchanged/)
  end

  it 'keeps status read-only without migrations or rendered actions' do
    expect(skill).to include('`Database.readonly_connection`')
    expect(skill).to match(/Do not run migrations/)
    expect(skill).to match(
      /Do not initialize, resume, rebase, retry, decide, squash,\s+or execute `Next:`/
    )
    expect(skill).to match(/Do not modify Git, Task files, or SQLite/)
  end
end
