# frozen_string_literal: true

class StartImplementationWorkCycle
  include ServiceObject

  arguments :review_id

  def call
    issue_ids = approved_issue_ids
    raise 'No approved issues remain for implementation' if issue_ids.empty?

    head_sha = ValidateWorkCycleGitState.call(project_path: review.fetch(:project_path))
    work_cycle_id = nil
    Database.connection.transaction(savepoint: true) do
      update_review(head_sha)
      work_cycle_id = create_work_cycle
      link_inputs(work_cycle_id, issue_ids)
    end
    work_cycle_id
  end

  private

  def approved_issue_ids
    existing_implementation_input_issue_ids = Database.connection[:work_cycle_inputs].
                                              join(:work_cycles, id: :work_cycle_id).
                                              where(Sequel[:work_cycles][:action] => 'implementation').
                                              select(Sequel[:work_cycle_inputs][:reported_issue_id])
    Database.connection[:reported_issues].
      join(:review_issues, reported_issue_id: :id).
      where(
        Sequel[:review_issues][:review_id] => review_id,
        Sequel[:reported_issues][:decision] => 'approved'
      ).
      exclude(Sequel[:reported_issues][:id] => existing_implementation_input_issue_ids).
      order(Sequel[:reported_issues][:id]).
      select_map(Sequel[:reported_issues][:id])
  end

  def review
    @review ||= Database.connection[:reviews].where(id: review_id).first
  end

  def update_review(head_sha)
    Database.connection[:reviews].where(id: review_id).update(
      starting_commit_sha: review.fetch(:starting_commit_sha) || head_sha,
      state: 'worker_implementation'
    )
  end

  def create_work_cycle
    Database.connection[:work_cycles].insert(
      created_at: Time.now,
      completed_at: nil,
      review_id: review_id,
      previous_work_cycle_id: nil,
      role: 'worker',
      action: 'implementation',
      result: nil,
      provider: nil,
      model: nil,
      reasoning_level: nil,
      commit_sha: nil
    )
  end

  def link_inputs(work_cycle_id, issue_ids)
    issue_ids.each do |issue_id|
      Database.connection[:work_cycle_inputs].insert(
        created_at: Time.now,
        work_cycle_id: work_cycle_id,
        reported_issue_id: issue_id
      )
    end
  end
end
