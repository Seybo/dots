# frozen_string_literal: true

require 'fileutils'
require 'open3'
require 'tmpdir'
require_relative 'spec_helper'

RSpec.describe FinalizeReview do
  let(:db) { Database.connection }
  let(:project_path) { Dir.mktmpdir('autofix-finalize-review-spec') }
  let(:tool_path) { Dir.mktmpdir('autofix-finalize-tools') }
  let(:command_log_path) { File.join(tool_path, 'commands.log') }
  let(:original_path) { ENV.fetch('PATH') }

  before do
    git!('init', '-q')
    git!('config', 'user.email', 'autofix@example.com')
    git!('config', 'user.name', 'Autofix')
    File.write(File.join(project_path, 'Gemfile'), "source 'https://rubygems.org'\n")
    File.write(File.join(project_path, 'tracked.txt'), "initial\n")
    git!('add', 'Gemfile', 'tracked.txt')
    git!('commit', '-q', '-m', 'Initial commit')
    write_fake_bundle
    ENV['PATH'] = "#{tool_path}:#{original_path}"
  end

  after do
    ENV['PATH'] = original_path
    FileUtils.remove_entry(project_path)
    FileUtils.remove_entry(tool_path)
  end

  it 'runs final checks, completes without squashing, and offers the optional squash' do
    review_id, implementation_work_cycle_id, _starting_commit_sha = create_implemented_review
    implementation_commit_sha = git!('rev-parse', 'HEAD').strip

    output = described_class.call(review_id: review_id)

    expect(output).to include(
      'Final checks:',
      '- bundle exec rubocop: passed (exit 0)',
      '- bundle exec rspec: passed (exit 0)',
      'Review 1 completed locally.',
      'Push: not performed.',
      "AutoFixSquash #{review_id}"
    )
    expect(File.readlines(command_log_path, chomp: true)).to eq(%w[rubocop rspec])
    expect(git!('rev-parse', 'HEAD').strip).to eq(implementation_commit_sha)
    expect(git!('log', '-1', '--format=%s').strip).to eq("Work cycle #{implementation_work_cycle_id}")
    expect(git!('status', '--porcelain')).to eq('')
    expect(db[:reviews].where(id: review_id).first).to include(
      state: 'completed',
      completed_at: be_a(Time)
    )
    expect(db[:work_cycles].where(id: implementation_work_cycle_id).get(:completed_at)).not_to be_nil
  end

  it 'reports both check results and reruns them on resume after a failure' do
    review_id, _implementation_work_cycle_id, _starting_commit_sha = create_implemented_review
    original_head = git!('rev-parse', 'HEAD').strip
    File.write(fail_check_path, '')

    output = described_class.call(review_id: review_id)

    expect(output).to include(
      '- bundle exec rubocop: failed (exit 3)',
      '- bundle exec rspec: passed (exit 0)',
      "bundle exec rubocop stdout:\nrubocop failed stdout",
      "bundle exec rubocop stderr:\nrubocop failed stderr",
      "bundle exec rspec stdout:\nrspec stdout",
      "bundle exec rspec stderr:\nrspec stderr"
    )
    expect(File.readlines(command_log_path, chomp: true)).to eq(%w[rubocop rspec])
    expect_unfinalized(review_id, original_head)

    FileUtils.rm_f(fail_check_path)
    resumed_output = ResumeReview.call(project_path: project_path, branch_name: 'feature')

    expect(resumed_output).to include('Review 1 completed locally.')
    expect(File.readlines(command_log_path, chomp: true)).to eq(%w[rubocop rspec rubocop rspec])
    expect(db[:reviews].where(id: review_id).get(:state)).to eq('completed')
  end

  it 'reruns checks after an interruption without storing partial progress' do
    review_id, _implementation_work_cycle_id, _starting_commit_sha = create_implemented_review
    original_head = git!('rev-parse', 'HEAD').strip
    interrupted_command = ['bash', '-c', 'bundle exec rubocop', { chdir: project_path }]
    allow(Open3).to receive(:capture3).and_call_original
    allow(Open3).to receive(:capture3).with(*interrupted_command).and_raise(Interrupt)

    expect { described_class.call(review_id: review_id) }.to raise_error(Interrupt)
    expect_unfinalized(review_id, original_head)

    allow(Open3).to receive(:capture3).with(*interrupted_command).and_call_original
    output = ResumeReview.call(project_path: project_path, branch_name: 'feature')

    expect(output).to include('Review 1 completed locally.')
    expect(File.readlines(command_log_path, chomp: true)).to eq(%w[rubocop rspec])
  end

  it 'fails before completion when a passing check dirties the tree' do
    review_id, _implementation_work_cycle_id, _starting_commit_sha = create_implemented_review
    original_head = git!('rev-parse', 'HEAD').strip
    File.write(dirty_check_path, '')

    expect { described_class.call(review_id: review_id) }.
      to raise_error(RuntimeError, /Working tree is not clean/)

    expect_unfinalized(review_id, original_head)
  end

  it 'fails before completion when Git history does not match the implementation Work Cycles' do
    review_id, _implementation_work_cycle_id, _starting_commit_sha = create_implemented_review
    File.write(File.join(project_path, 'unrelated.txt'), "unrelated\n")
    git!('add', 'unrelated.txt')
    git!('commit', '-q', '-m', 'Unrelated commit')
    original_head = git!('rev-parse', 'HEAD').strip

    expect { described_class.call(review_id: review_id) }.
      to raise_error(RuntimeError, /commit sequence does not match/)

    expect_unfinalized(review_id, original_head)
    expect(git!('log', '-1', '--format=%s').strip).to eq('Unrelated commit')
  end

  private

  def fail_check_path
    File.join(tool_path, 'fail-rubocop')
  end

  def dirty_check_path
    File.join(tool_path, 'dirty-rspec')
  end

  def create_implemented_review
    review_id = StoreReview.call(
      project_path: project_path,
      source: 'local',
      branch_name: 'feature',
      base_ref: 'origin/main',
      base_commit_sha: 'base-sha',
      issue_data: [{ source_id: nil, body: 'Approved issue.' }]
    )
    issue_id = db[:review_issues].where(review_id: review_id).get(:reported_issue_id)
    db[:reported_issues].where(id: issue_id).update(decision: 'approved')
    implementation_work_cycle_id = StartImplementationWorkCycle.call(review_id: review_id)
    starting_commit_sha = db[:reviews].where(id: review_id).get(:starting_commit_sha)
    File.write(File.join(project_path, 'tracked.txt'), "implemented\n")
    git!('add', 'tracked.txt')
    git!('commit', '-q', '-m', "Work cycle #{implementation_work_cycle_id}")
    db[:work_cycles].where(id: implementation_work_cycle_id).update(completed_at: Time.now)
    db[:reviews].where(id: review_id).update(state: 'manager_finalizing')

    [review_id, implementation_work_cycle_id, starting_commit_sha]
  end

  def expect_unfinalized(review_id, head_sha)
    expect(db[:reviews].where(id: review_id).first).to include(
      state: 'manager_finalizing',
      completed_at: nil
    )
    expect(git!('rev-parse', 'HEAD').strip).to eq(head_sha)
  end

  def write_fake_bundle
    File.write(
      File.join(tool_path, 'bundle'),
      <<~SH
        #!/bin/sh
        printf '%s\\n' "$2" >> "#{command_log_path}"
        if [ "$2" = rubocop ] && [ -f "#{fail_check_path}" ]; then
          printf 'rubocop failed stdout\\n'
          printf 'rubocop failed stderr\\n' >&2
          exit 3
        fi
        printf '%s stdout\\n' "$2"
        printf '%s stderr\\n' "$2" >&2
        if [ "$2" = rspec ] && [ -f "#{dirty_check_path}" ]; then
          printf 'dirty\\n' > "#{File.join(project_path, 'tracked.txt')}"
        fi
      SH
    )
    File.chmod(0o755, File.join(tool_path, 'bundle'))
  end

  def git!(*arguments)
    stdout, stderr, status = Open3.capture3('git', '-C', project_path, *arguments)
    raise stderr unless status.success?

    stdout
  end
end
