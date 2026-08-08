# frozen_string_literal: true

require_relative '../../spec/spec_helper'

RSpec.describe RunTaskFinalChecks do
  let(:db) { Database.connection }
  let(:task_id) do
    db[:tasks].insert(
      created_at: Time.now,
      task_path: '/tasks/1',
      project_path: '/project',
      branch_name: 'feature',
      starting_commit_sha: 'starting-sha',
      state: 'manager_review'
    )
  end
  let(:manager_work_cycle_id) do
    db[:work_cycles].insert(
      created_at: Time.now,
      completed_at: Time.now,
      task_id: task_id,
      role: 'manager',
      action: 'review'
    )
  end
  let(:passing_result) do
    {
      output: "Final checks:\n- bundle exec rubocop: passed (exit 0)",
      is_passing: true
    }
  end

  before do
    manager_work_cycle_id
    allow(RunFinalChecks).to receive(:call).and_return(passing_result)
    allow(ValidateCleanGitState).to receive(:call).and_return('checked-head')
    allow(CommitWorkCycle).to receive(:call)
  end

  it 'stores only terminal completion after passing checks and clean Git' do
    output = described_class.call(task_id: task_id)

    expect(output).to eq(
      "Final checks:\n- bundle exec rubocop: passed (exit 0)\n" \
      "Task #{task_id} completed locally.\n" \
      "Push: not performed.\n" \
      "AutoImplementSquash #{task_id}"
    )
    expect(RunFinalChecks).to have_received(:call).with(project_path: '/project')
    expect(ValidateCleanGitState).to have_received(:call).with(project_path: '/project')
    expect(db[:tasks].where(id: task_id).get(:state)).to eq('final_checks_passed')
    expect(CommitWorkCycle).not_to have_received(:call)
    expect(db[:work_cycles].count).to eq(1)
    expect(db[:reported_issues].count).to eq(0)
  end

  it 'stores the same completion after the no-Gemfile skip' do
    allow(RunFinalChecks).to receive(:call).and_return(
      output: "Final checks:\nSkipped: no Gemfile.",
      is_passing: true
    )

    output = described_class.call(task_id: task_id)

    expect(output).to eq(
      "Final checks:\nSkipped: no Gemfile.\n" \
      "Task #{task_id} completed locally.\n" \
      "Push: not performed.\n" \
      "AutoImplementSquash #{task_id}"
    )
    expect(db[:tasks].where(id: task_id).get(:state)).to eq('final_checks_passed')
  end

  it 'refuses checks outside the settled Manager state' do
    db[:tasks].where(id: task_id).update(state: 'worker_final_review')

    expect { described_class.call(task_id: task_id) }.
      to raise_error(RuntimeError, "Task #{task_id} cannot run final checks from state worker_final_review")

    expect(RunFinalChecks).not_to have_received(:call)
    expect(ValidateCleanGitState).not_to have_received(:call)
  end

  it 'refuses checks without a completed Manager review' do
    db[:work_cycles].where(id: manager_work_cycle_id).delete

    expect { described_class.call(task_id: task_id) }.
      to raise_error(RuntimeError, "Task #{task_id} latest Manager review is not settled")

    expect(RunFinalChecks).not_to have_received(:call)
  end

  it 'refuses checks when the latest Manager review has an undecided issue' do
    issue_id = StoreIssue.call(project_path: '/project', source: 'manager', body: 'Manager issue.')
    db[:work_cycle_reported_issues].insert(
      created_at: Time.now,
      work_cycle_id: manager_work_cycle_id,
      reported_issue_id: issue_id
    )

    expect { described_class.call(task_id: task_id) }.
      to raise_error(RuntimeError, "Task #{task_id} latest Manager review is not settled")

    expect(RunFinalChecks).not_to have_received(:call)
  end

  it 'returns failed output without checking Git or changing workflow state' do
    allow(RunFinalChecks).to receive(:call).and_return(
      output: "Final checks:\n- bundle exec rubocop: failed (exit 1)",
      is_passing: false
    )

    output = described_class.call(task_id: task_id)

    expect(output).to eq("Final checks:\n- bundle exec rubocop: failed (exit 1)")
    expect(ValidateCleanGitState).not_to have_received(:call)
    expect_unchanged_workflow
  end

  it 'leaves workflow state unchanged when checks are interrupted' do
    allow(RunFinalChecks).to receive(:call).and_raise(Interrupt)

    expect { described_class.call(task_id: task_id) }.to raise_error(Interrupt)

    expect(ValidateCleanGitState).not_to have_received(:call)
    expect_unchanged_workflow
  end

  it 'leaves workflow state unchanged when passing checks dirty the project' do
    allow(ValidateCleanGitState).to receive(:call).and_raise('Working tree is not clean')

    expect { described_class.call(task_id: task_id) }.
      to raise_error(RuntimeError, 'Working tree is not clean')

    expect_unchanged_workflow
  end

  it 'leaves workflow state unchanged when the Task transition fails' do
    allow(db).to receive(:transaction).and_raise(Sequel::DatabaseError, 'database failed')

    expect { described_class.call(task_id: task_id) }.
      to raise_error(Sequel::DatabaseError, 'database failed')

    expect_unchanged_workflow
  end

  private

  def expect_unchanged_workflow
    expect(db[:tasks].where(id: task_id).get(:state)).to eq('manager_review')
    expect(CommitWorkCycle).not_to have_received(:call)
    expect(db[:work_cycles].count).to eq(1)
    expect(db[:reported_issues].count).to eq(0)
  end
end
