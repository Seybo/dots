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

  it 'commits a completed implementation and stores its completion and provenance' do
    review_id, work_cycle_id = start_implementation
    File.write(File.join(project_path, 'tracked.txt'), "implemented\n")
    write_result(work_cycle_id, completed_result(work_cycle_id))

    output = described_class.call(work_cycle_id: work_cycle_id)
    review_work_cycle = db[:work_cycles].exclude(id: work_cycle_id).first

    expect(output).to eq(
      "Worker implementation completed (Cycle #{work_cycle_id}).\n" \
      "AutoFixCycle #{review_work_cycle.fetch(:id)}\n" \
      'AutoFixRole reviewer'
    )
    expect(git!('log', '-1', '--format=%s').strip).to eq("Work cycle #{work_cycle_id}")
    expect(db[:work_cycles].where(id: work_cycle_id).first).to include(
      provider: 'openai-codex',
      model: 'gpt-5.6-sol',
      reasoning_level: 'high'
    )
    expect(db[:work_cycles].where(id: work_cycle_id).get(:completed_at)).not_to be_nil
    expect(review_work_cycle).to include(
      review_id: review_id,
      role: 'reviewer',
      action: 'review'
    )
    expect(db[:reviews].where(id: review_id).get(:state)).to eq('reviewer_review')
    expect(File.exist?(result_path(work_cycle_id))).to be(false)
  end

  it 'commits a later implementation and creates its Reviewer review Work Cycle' do
    review_id, _first_implementation_id, reviewer_work_cycle_id = start_reviewer_review
    StoreWorkCycleCompletion.call(
      work_cycle_id: reviewer_work_cycle_id,
      work_cycle_result: review_result(
        reviewer_work_cycle_id,
        role: 'reviewer',
        reported_issues: ['Reviewer-reported issue.']
      )
    )
    reported_issue = db[:reported_issues].where(source: 'reviewer').first
    HandleDecision.call(issue_id: reported_issue.fetch(:id), decision: 'approved')
    later_work_cycle = db[:work_cycles].order(:id).last
    allow(Database).to receive(:readonly_connection).and_return(db)
    context = JSON.parse(ShowWorkCycle.call(work_cycle_id: later_work_cycle.fetch(:id)))
    work_cycle_count = db[:work_cycles].count

    File.write(File.join(project_path, 'tracked.txt'), "implemented again\n")
    write_result(later_work_cycle.fetch(:id), completed_result(later_work_cycle.fetch(:id)))

    output = described_class.call(work_cycle_id: later_work_cycle.fetch(:id))
    next_reviewer_work_cycle = db[:work_cycles].order(:id).last

    expect(output).to eq(
      "Worker implementation completed (Cycle #{later_work_cycle.fetch(:id)}).\n" \
      "AutoFixCycle #{next_reviewer_work_cycle.fetch(:id)}\n" \
      'AutoFixRole reviewer'
    )
    expect(context.fetch('inputs')).to eq(
      [
        {
          'id' => reported_issue.fetch(:id),
          'source' => 'reviewer',
          'body' => 'Reviewer-reported issue.'
        },
      ]
    )
    expect(db[:work_cycles].count).to eq(work_cycle_count + 1)
    expect(db[:work_cycles].where(role: 'reviewer', action: 'review').count).to eq(2)
    expect(db[:work_cycle_inputs].where(work_cycle_id: next_reviewer_work_cycle.fetch(:id)).
      select_map(:reported_issue_id)).to eq([reported_issue.fetch(:id)])
    expect(db[:work_cycles].where(id: later_work_cycle.fetch(:id)).first).to include(
      completed_at: be_a(Time),
      provider: 'openai-codex',
      model: 'gpt-5.6-sol',
      reasoning_level: 'high'
    )
    expect(db[:reviews].where(id: review_id).get(:state)).to eq('reviewer_review')
    expect(db[:review_issues].where(review_id: review_id).count).to eq(2)
    expect(git!('log', '-1', '--format=%s').strip).to eq("Work cycle #{later_work_cycle.fetch(:id)}")
    expect(git!('status', '--porcelain')).to eq('')
    expect(File.exist?(result_path(later_work_cycle.fetch(:id)))).to be(false)
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
      completed_at: be_a(Time)
    )
    expect(db[:reviews].where(id: review_id).get(:state)).to eq('reviewer_review')
    expect(db[:work_cycles].count).to eq(1)
    expect(File.exist?(result_path(work_cycle_id))).to be(false)

    git!('restore', 'tracked.txt')
    output = ResumeReview.call(project_path: project_path, branch_name: 'feature')
    reviewer_work_cycle = db[:work_cycles].order(:id).last

    expect(output).to eq("AutoFixCycle #{reviewer_work_cycle.fetch(:id)}\nAutoFixRole reviewer")
    expect(db[:work_cycles].count).to eq(2)
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
    expect(db[:work_cycles].where(id: work_cycle_id).first).to include(completed_at: nil)
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
      completed_at: nil
    )
  end

  it 'stores Reviewer-reported issues and displays the first unresolved issue without starting Worker review' do
    review_id, _implementation_work_cycle_id, reviewer_work_cycle_id = start_reviewer_review
    original_head = git!('rev-parse', 'HEAD').strip
    review_result = review_result(
      reviewer_work_cycle_id,
      role: 'reviewer',
      reported_issues: ['Reviewer-reported issue.']
    )
    write_result(reviewer_work_cycle_id, review_result)

    output = described_class.call(work_cycle_id: reviewer_work_cycle_id)
    reported_issue = db[:reported_issues].where(source: 'reviewer').first

    expect(output).to eq(
      "Reviewer review completed (Cycle #{reviewer_work_cycle_id}). Reported issues:\n- Reviewer-reported issue.\n\n" \
      "Issue: #{reported_issue.fetch(:id)}\n\n> Reviewer-reported issue."
    )
    expect(git!('rev-parse', 'HEAD').strip).to eq(original_head)
    expect(db[:work_cycles].where(id: reviewer_work_cycle_id).first).to include(
      completed_at: be_a(Time)
    )
    expect(db[:reviews].where(id: review_id).get(:state)).to eq('manager_issues_assessment')
    expect(db[:work_cycles].count).to eq(2)
    expect(File.exist?(result_path(reviewer_work_cycle_id))).to be(false)
  end

  it 'starts one final Worker review after Reviewer reports no issues' do
    review_id, _implementation_work_cycle_id, reviewer_work_cycle_id = start_reviewer_review
    write_result(
      reviewer_work_cycle_id,
      review_result(reviewer_work_cycle_id, role: 'reviewer', reported_issues: [])
    )

    output = described_class.call(work_cycle_id: reviewer_work_cycle_id)
    worker_work_cycle = db[:work_cycles].order(:id).last

    expect(output).to eq(
      "Reviewer review completed (Cycle #{reviewer_work_cycle_id}). Reported issues:\n- None\n" \
      "AutoFixCycle #{worker_work_cycle.fetch(:id)}\n" \
      'AutoFixRole worker'
    )
    expect(worker_work_cycle).to include(
      review_id: review_id,
      role: 'worker',
      action: 'review'
    )
    expect(db[:reviews].where(id: review_id).get(:state)).to eq('worker_review')
    expect(File.exist?(result_path(reviewer_work_cycle_id))).to be(false)
  end

  it 'repeats implementation and Reviewer loops after Worker review without another Worker review' do
    review_id, first_implementation_id, first_reviewer_work_cycle_id = start_reviewer_review
    StoreWorkCycleCompletion.call(
      work_cycle_id: first_reviewer_work_cycle_id,
      work_cycle_result: review_result(
        first_reviewer_work_cycle_id,
        role: 'reviewer',
        reported_issues: []
      )
    )
    worker_work_cycle_id = StartWorkerReviewWorkCycle.call(review_id: review_id)
    StoreWorkCycleCompletion.call(
      work_cycle_id: worker_work_cycle_id,
      work_cycle_result: review_result(
        worker_work_cycle_id,
        role: 'worker',
        reported_issues: ['Worker-reported issue.']
      )
    )
    worker_issue_id = db[:reported_issues].where(source: 'worker').get(:id)
    db[:reported_issues].where(id: worker_issue_id).update(decision: 'approved')
    second_implementation_id = StartImplementationWorkCycle.call(review_id: review_id)
    StoreWorkCycleCompletion.call(
      work_cycle_id: second_implementation_id,
      work_cycle_result: completed_result(second_implementation_id)
    )
    second_reviewer_work_cycle_id = StartReviewerReviewWorkCycle.call(review_id: review_id)
    write_result(
      second_reviewer_work_cycle_id,
      review_result(
        second_reviewer_work_cycle_id,
        role: 'reviewer',
        reported_issues: ['Reviewer-reported issue.']
      )
    )

    described_class.call(work_cycle_id: second_reviewer_work_cycle_id)
    reviewer_issue_id = db[:reported_issues].where(source: 'reviewer').get(:id)
    HandleDecision.call(issue_id: reviewer_issue_id, decision: 'approved')
    third_implementation_id = db[:work_cycles].where(action: 'implementation').order(:id).last.fetch(:id)
    StoreWorkCycleCompletion.call(
      work_cycle_id: third_implementation_id,
      work_cycle_result: completed_result(third_implementation_id)
    )
    third_reviewer_work_cycle_id = StartReviewerReviewWorkCycle.call(review_id: review_id)
    write_result(
      third_reviewer_work_cycle_id,
      review_result(third_reviewer_work_cycle_id, role: 'reviewer', reported_issues: [])
    )

    output = described_class.call(work_cycle_id: third_reviewer_work_cycle_id)

    expect(output).to eq(
      "Reviewer review completed (Cycle #{third_reviewer_work_cycle_id}). Reported issues:\n- None"
    )
    expect(db[:reviews].where(id: review_id).get(:state)).to eq('manager_review')
    expect(db[:work_cycles].where(role: 'worker', action: 'review').count).to eq(1)
    expect(db[:work_cycle_inputs].where(work_cycle_id: second_implementation_id).
      select_map(:reported_issue_id)).to eq([worker_issue_id])
    expect(db[:work_cycle_inputs].where(work_cycle_id: third_implementation_id).
      select_map(:reported_issue_id)).to eq([reviewer_issue_id])
    expect(
      [
        first_implementation_id,
        first_reviewer_work_cycle_id,
        worker_work_cycle_id,
        second_implementation_id,
        second_reviewer_work_cycle_id,
        third_implementation_id,
        third_reviewer_work_cycle_id,
      ]
    ).to eq(db[:work_cycles].order(:id).select_map(:id))
    expect(File.exist?(result_path(third_reviewer_work_cycle_id))).to be(false)
  end

  it 'stores final Worker-reported issues without creating a commit' do
    review_id, _implementation_work_cycle_id, reviewer_work_cycle_id = start_reviewer_review
    db[:work_cycles].where(id: reviewer_work_cycle_id).update(
      completed_at: Time.now
    )
    db[:reviews].where(id: review_id).update(state: 'worker_review')
    worker_work_cycle_id = StartWorkerReviewWorkCycle.call(review_id: review_id)
    original_head = git!('rev-parse', 'HEAD').strip
    result = review_result(worker_work_cycle_id, role: 'worker', reported_issues: ['Worker-reported issue.'])
    write_result(worker_work_cycle_id, result)

    output = described_class.call(work_cycle_id: worker_work_cycle_id)
    reported_issue = db[:reported_issues].where(source: 'worker').first

    expect(output).to eq(
      "Worker review completed (Cycle #{worker_work_cycle_id}). Reported issues:\n- Worker-reported issue.\n\n" \
      "Issue: #{reported_issue.fetch(:id)}\n\n> Worker-reported issue."
    )
    expect(git!('rev-parse', 'HEAD').strip).to eq(original_head)
    expect(db[:work_cycles].where(id: worker_work_cycle_id).first).to include(
      completed_at: be_a(Time)
    )
    expect(db[:reviews].where(id: review_id).get(:state)).to eq('manager_issues_assessment')
    expect(File.exist?(result_path(worker_work_cycle_id))).to be(false)
  end

  it 'retains a review result when Reported Issue persistence rolls back' do
    review_id, _implementation_work_cycle_id, reviewer_work_cycle_id = start_reviewer_review
    result = review_result(
      reviewer_work_cycle_id,
      role: 'reviewer',
      reported_issues: ['Rolled back issue.', nil]
    )
    write_result(reviewer_work_cycle_id, result)

    expect { described_class.call(work_cycle_id: reviewer_work_cycle_id) }.
      to raise_error(Sequel::NotNullConstraintViolation)

    expect(db[:work_cycles].where(id: reviewer_work_cycle_id).first).to include(
      completed_at: nil
    )
    expect(db[:reviews].where(id: review_id).get(:state)).to eq('reviewer_review')
    expect(db[:reported_issues].where(source: 'reviewer').count).to eq(0)
    expect(File.exist?(result_path(reviewer_work_cycle_id))).to be(true)
  end

  def start_implementation
    review_id = store_review
    issue_id = db[:review_issues].where(review_id: review_id).get(:reported_issue_id)
    db[:reported_issues].where(id: issue_id).update(decision: 'approved')
    [review_id, StartImplementationWorkCycle.call(review_id: review_id)]
  end

  def start_reviewer_review
    review_id, implementation_work_cycle_id = start_implementation
    File.write(File.join(project_path, 'tracked.txt'), "implemented\n")
    git!('add', 'tracked.txt')
    git!('commit', '-q', '-m', 'Implementation')
    db[:work_cycles].where(id: implementation_work_cycle_id).update(
      completed_at: Time.now
    )
    db[:reviews].where(id: review_id).update(state: 'reviewer_review')
    reviewer_work_cycle_id = StartReviewerReviewWorkCycle.call(review_id: review_id)

    [review_id, implementation_work_cycle_id, reviewer_work_cycle_id]
  end

  def review_result(work_cycle_id, role:, reported_issues:)
    completed_result(work_cycle_id).merge(
      'role' => role,
      'action' => 'review',
      'reported_issues' => reported_issues
    )
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
