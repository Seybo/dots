# frozen_string_literal: true

require 'json'
require 'open3'
require 'tmpdir'
require_relative '../../spec/spec_helper'

RSpec.describe RetryTaskWorkCycle do
  let(:db) { Database.connection }
  let(:project_path) { Dir.mktmpdir('retry-task-work-cycle-spec') }
  let(:task_id) do
    db[:tasks].insert(
      created_at: Time.now,
      task_path: File.join(project_path, 'task'),
      project_path: project_path,
      starting_commit_sha: git!('rev-parse', 'HEAD').strip,
      state: 'initialized',
      super_review_agent: 'claude'
    )
  end
  let(:work_cycle_id) { insert_work_cycle }
  let(:created_result_paths) { [] }

  before do
    git!('init', '-q', '--initial-branch=main')
    git!('config', 'user.email', 'autowork@example.com')
    git!('config', 'user.name', 'Autowork')
    File.write(File.join(project_path, 'tracked.txt'), "initial\n")
    git!('add', 'tracked.txt')
    git!('commit', '-q', '-m', 'Initial commit')
  end

  after do
    created_result_paths.each { |path| FileUtils.rm_f(path) }
    FileUtils.remove_entry(project_path)
  end

  it 'redispatches the same incomplete Work Cycle when transport is missing' do
    original_task = db[:tasks].where(id: task_id).first
    original_work_cycle = db[:work_cycles].where(id: work_cycle_id).first

    expect(described_class.call(task_id: task_id)).to eq("AutoImplementCycle #{work_cycle_id}")

    expect(db[:tasks].where(id: task_id).first).to eq(original_task)
    expect(db[:work_cycles].where(id: work_cycle_id).first).to eq(original_work_cycle)
  end

  it 'deletes a failed result and redispatches the same incomplete Work Cycle' do
    write_result(valid_result.merge('status' => 'failed', 'error' => 'Could not finish.'))

    expect(described_class.call(task_id: task_id)).to eq("AutoImplementCycle #{work_cycle_id}")
    expect(File.exist?(result_path)).to be(false)
    expect(db[:work_cycles].where(id: work_cycle_id).get(:completed_at)).to be_nil
  end

  it 'deletes malformed or invalid result transport before redispatch' do
    invalid_results = [
      '{',
      'null',
      '[]',
      JSON.generate(valid_result.except('provider')),
      JSON.generate(valid_result.merge('status' => 'pending')),
      JSON.generate(valid_result.merge('work_cycle_id' => work_cycle_id + 1)),
      JSON.generate(valid_result.merge('role' => 'reviewer')),
      JSON.generate(valid_result.merge('action' => 'review')),
    ]

    invalid_results.each do |contents|
      write_raw_result(contents)

      expect(described_class.call(task_id: task_id)).to eq("AutoImplementCycle #{work_cycle_id}")
      expect(File.exist?(result_path)).to be(false)
    end
  end

  it 'rejects a dirty project before deleting retryable transport' do
    write_result(valid_result.merge('status' => 'failed', 'error' => 'Could not finish.'))
    File.write(File.join(project_path, 'tracked.txt'), "changed\n")

    expect { described_class.call(task_id: task_id) }.
      to raise_error(
        RuntimeError,
        /Task #{task_id} Work Cycle #{work_cycle_id} retry Git validation failed.*discard.*--retry/
      )

    expect(File.exist?(result_path)).to be(true)
    expect(db[:work_cycles].where(id: work_cycle_id).get(:completed_at)).to be_nil
  end

  it 'retains transport when retry cleanup fails' do
    write_result(valid_result.merge('status' => 'failed', 'error' => 'Could not finish.'))
    allow(File).to receive(:delete).with(result_path).and_raise(Errno::EACCES)

    error_pattern = Regexp.new(
      "Task #{task_id} Work Cycle #{work_cycle_id} retry transport cleanup failed at .*" \
      "#{work_cycle_id}\\.json.*ad-hoc Manager handling"
    )
    expect { described_class.call(task_id: task_id) }.
      to raise_error(RuntimeError, error_pattern)

    expect(File.exist?(result_path)).to be(true)
    expect(db[:work_cycles].where(id: work_cycle_id).get(:completed_at)).to be_nil
  end

  it 'rejects a Task without an incomplete Work Cycle' do
    db[:work_cycles].where(id: work_cycle_id).update(completed_at: Time.now)

    expect { described_class.call(task_id: task_id) }.
      to raise_error(RuntimeError, "Task #{task_id} has no incomplete Work Cycle to retry")
  end

  it 'rejects a Task with multiple incomplete Work Cycles' do
    work_cycle_id
    insert_work_cycle

    expect { described_class.call(task_id: task_id) }.
      to raise_error(RuntimeError, "Task #{task_id} has 2 incomplete Work Cycles; handle this state ad hoc")
  end

  it 'retains and rejects a valid completed result' do
    write_result(valid_result)

    expect { described_class.call(task_id: task_id) }.
      to raise_error(
        RuntimeError,
        "Task #{task_id} Work Cycle #{work_cycle_id} has a valid completed result; resume it normally"
      )

    expect(File.exist?(result_path)).to be(true)
    expect(db[:work_cycles].where(id: work_cycle_id).get(:completed_at)).to be_nil
  end

  private

  def insert_work_cycle
    db[:work_cycles].insert(
      created_at: Time.now,
      completed_at: nil,
      task_id: task_id,
      step_number: 1,
      role: 'worker',
      action: 'implementation'
    )
  end

  def valid_result
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

  def write_result(result)
    write_raw_result(JSON.generate(result))
  end

  def write_raw_result(contents)
    created_result_paths << result_path unless created_result_paths.include?(result_path)
    File.write(result_path, contents)
  end

  def result_path
    "/tmp/autoimplement-work-cycle-#{work_cycle_id}.json"
  end

  def git!(*arguments)
    stdout, stderr, status = Open3.capture3('git', '-C', project_path, *arguments)
    raise stderr unless status.success?

    stdout
  end
end
