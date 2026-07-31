# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'open3'
require 'tmpdir'
require_relative 'spec_helper'

RSpec.describe WaitWorkCycle do
  let(:db) { Database.connection }
  let(:project_path) { Dir.mktmpdir('autofix-wait-work-cycle-spec') }
  let(:created_result_paths) { [] }

  before do
    git!('init', '-q')
    git!('config', 'user.email', 'autofix@example.com')
    git!('config', 'user.name', 'Autofix')
    File.write(File.join(project_path, 'tracked.txt'), "initial\n")
    git!('add', 'tracked.txt')
    git!('commit', '-q', '-m', 'Initial commit')
  end

  after do
    created_result_paths.each { |path| FileUtils.rm_f(path) }
    FileUtils.remove_entry(project_path)
  end

  it 'commits a completed implementation and stores its result and provenance' do
    review_id, work_cycle_id = start_implementation
    File.write(File.join(project_path, 'tracked.txt'), "implemented\n")
    write_result(work_cycle_id, completed_result(work_cycle_id))

    output = described_class.call(work_cycle_id: work_cycle_id)
    commit_sha = git!('rev-parse', 'HEAD').strip
    review_work_cycle = db[:work_cycles].exclude(id: work_cycle_id).first

    expect(output).to eq(
      "Work Cycle #{work_cycle_id} completed at #{commit_sha}.\n" \
      "AutoFixCycle #{review_work_cycle.fetch(:id)}"
    )
    expect(git!('log', '-1', '--format=%s').strip).to eq("Work cycle #{work_cycle_id}")
    expect(db[:work_cycles].where(id: work_cycle_id).first).to include(
      result: JSON.generate(completed_result(work_cycle_id)),
      provider: 'openai-codex',
      model: 'gpt-5.6-sol',
      reasoning_level: 'high',
      commit_sha: commit_sha
    )
    expect(db[:work_cycles].where(id: work_cycle_id).get(:completed_at)).not_to be_nil
    expect(review_work_cycle).to include(
      review_id: review_id,
      previous_work_cycle_id: work_cycle_id,
      role: 'worker',
      action: 'review'
    )
    expect(db[:reviews].where(id: review_id).get(:state)).to eq('worker_review')
    expect(File.exist?(result_path(work_cycle_id))).to be(false)
  end

  it 'does not reprocess a committed result when the tree becomes dirty before review' do
    review_id, work_cycle_id = start_implementation
    File.write(File.join(project_path, 'tracked.txt'), "implemented\n")
    hook_path = File.join(project_path, '.git', 'hooks', 'post-commit')
    File.write(hook_path, "#!/bin/sh\nprintf 'dirty\\n' > tracked.txt\n")
    File.chmod(0o755, hook_path)
    write_result(work_cycle_id, completed_result(work_cycle_id))

    expect { described_class.call(work_cycle_id: work_cycle_id) }.
      to raise_error(RuntimeError, /Working tree is not clean/)

    expect(db[:work_cycles].where(id: work_cycle_id).first).to include(
      result: JSON.generate(completed_result(work_cycle_id)),
      completed_at: be_a(Time),
      commit_sha: git!('rev-parse', 'HEAD').strip
    )
    expect(db[:reviews].where(id: review_id).get(:state)).to eq('worker_review')
    expect(db[:work_cycles].count).to eq(1)
    expect(File.exist?(result_path(work_cycle_id))).to be(false)
  end

  it 'stores null provenance without inference' do
    _review_id, work_cycle_id = start_implementation
    File.write(File.join(project_path, 'tracked.txt'), "implemented\n")
    write_result(
      work_cycle_id,
      completed_result(work_cycle_id).merge(
        'provider' => nil,
        'model' => nil,
        'reasoning_level' => nil
      )
    )

    described_class.call(work_cycle_id: work_cycle_id)

    expect(db[:work_cycles].where(id: work_cycle_id).first).to include(
      provider: nil,
      model: nil,
      reasoning_level: nil
    )
  end

  it 'exposes a failed result without changing Git or Work Cycle state' do
    review_id, work_cycle_id = start_implementation
    original_head = git!('rev-parse', 'HEAD').strip
    write_result(
      work_cycle_id,
      completed_result(work_cycle_id).merge(
        'status' => 'failed',
        'error' => 'Implementation could not continue.'
      )
    )

    expect { described_class.call(work_cycle_id: work_cycle_id) }.
      to raise_error(RuntimeError, "Work Cycle #{work_cycle_id} failed: Implementation could not continue.")

    expect(git!('rev-parse', 'HEAD').strip).to eq(original_head)
    expect(db[:work_cycles].where(id: work_cycle_id).first).to include(result: nil, completed_at: nil)
    expect(db[:reviews].where(id: review_id).get(:state)).to eq('worker_implementation')
    expect(File.exist?(result_path(work_cycle_id))).to be(true)
  end

  it 'retains malformed result JSON' do
    _review_id, work_cycle_id = start_implementation
    path = result_path(work_cycle_id)
    created_result_paths << path
    File.write(path, '{')

    expect { described_class.call(work_cycle_id: work_cycle_id) }.to raise_error(JSON::ParserError)

    expect(File.exist?(result_path(work_cycle_id))).to be(true)
    expect(db[:work_cycles].where(id: work_cycle_id).get(:completed_at)).to be_nil
  end

  it 'rejects mismatched Work Cycle identity and retains the result' do
    _review_id, work_cycle_id = start_implementation
    mismatches = [
      { 'work_cycle_id' => work_cycle_id + 1 },
      { 'role' => 'reviewer' },
      { 'action' => 'review' },
    ]

    mismatches.each do |mismatch|
      write_result(work_cycle_id, completed_result(work_cycle_id).merge(mismatch))

      expect { described_class.call(work_cycle_id: work_cycle_id) }.
        to raise_error(RuntimeError, /does not match Work Cycle #{work_cycle_id}/)
      expect(File.exist?(result_path(work_cycle_id))).to be(true)
    end

    expect(db[:work_cycles].where(id: work_cycle_id).get(:completed_at)).to be_nil
  end

  it 'rejects an unsupported status and retains the result' do
    _review_id, work_cycle_id = start_implementation
    write_result(work_cycle_id, completed_result(work_cycle_id).merge('status' => 'pending'))

    expect { described_class.call(work_cycle_id: work_cycle_id) }.
      to raise_error(RuntimeError, 'Unsupported Work Cycle result status: pending')

    expect(File.exist?(result_path(work_cycle_id))).to be(true)
    expect(db[:work_cycles].where(id: work_cycle_id).get(:completed_at)).to be_nil
  end

  it 'retains the result when implementation produced no committable changes' do
    _review_id, work_cycle_id = start_implementation
    write_result(work_cycle_id, completed_result(work_cycle_id))

    expect { described_class.call(work_cycle_id: work_cycle_id) }.
      to raise_error(RuntimeError, /git .* commit .* failed/)

    expect(File.exist?(result_path(work_cycle_id))).to be(true)
    expect(db[:work_cycles].where(id: work_cycle_id).first).to include(
      result: nil,
      completed_at: nil,
      commit_sha: nil
    )
  end

  it 'completes a review Work Cycle without creating a commit' do
    review_id = store_review
    db[:reviews].where(id: review_id).update(state: 'worker_review')
    work_cycle_id = db[:work_cycles].insert(
      created_at: Time.now,
      completed_at: nil,
      review_id: review_id,
      previous_work_cycle_id: nil,
      role: 'worker',
      action: 'review',
      result: nil,
      provider: nil,
      model: nil,
      reasoning_level: nil,
      commit_sha: nil
    )
    original_head = git!('rev-parse', 'HEAD').strip
    review_result = completed_result(work_cycle_id).merge(
      'action' => 'review',
      'findings' => ['Review finding.']
    )
    write_result(work_cycle_id, review_result)

    output = described_class.call(work_cycle_id: work_cycle_id)

    expect(output).to eq("Work Cycle #{work_cycle_id} completed. Findings:\n- Review finding.")
    expect(git!('rev-parse', 'HEAD').strip).to eq(original_head)
    expect(db[:work_cycles].where(id: work_cycle_id).first).to include(
      result: JSON.generate(review_result),
      completed_at: be_a(Time),
      commit_sha: nil
    )
    expect(db[:reviews].where(id: review_id).get(:state)).to eq('reviewer_review')
    expect(File.exist?(result_path(work_cycle_id))).to be(false)
  end

  def start_implementation
    review_id = store_review
    issue_id = db[:review_issues].where(review_id: review_id).get(:reported_issue_id)
    db[:reported_issues].where(id: issue_id).update(decision: 'approved')
    [review_id, StartImplementationWorkCycle.call(review_id: review_id)]
  end

  def store_review
    StoreReview.call(
      project_path: project_path,
      source: 'local',
      branch_name: 'feature',
      base_ref: 'origin/main',
      base_commit_sha: 'base-sha',
      issue_data: [{ source_id: nil, body: 'Approved issue.' }]
    )
  end

  def completed_result(work_cycle_id)
    {
      'work_cycle_id' => work_cycle_id,
      'role' => 'worker',
      'action' => 'implementation',
      'status' => 'completed',
      'provider' => 'openai-codex',
      'model' => 'gpt-5.6-sol',
      'reasoning_level' => 'high'
    }
  end

  def write_result(work_cycle_id, result)
    path = result_path(work_cycle_id)
    created_result_paths << path unless created_result_paths.include?(path)
    File.write(path, JSON.generate(result))
  end

  def result_path(work_cycle_id)
    "/tmp/autofix-work-cycle-#{work_cycle_id}.json"
  end

  def git!(*arguments)
    stdout, stderr, status = Open3.capture3('git', '-C', project_path, *arguments)
    raise stderr unless status.success?

    stdout
  end
end
