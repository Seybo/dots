# frozen_string_literal: true

class StartImplementationWorkCycle
  include ServiceObject

  arguments :review_id

  def call
    issue_ids = approved_issue_ids
    return if issue_ids.empty?

    ValidateCleanGitState.call(project_path: review_context.fetch(:project_path))
    Database.connection.transaction(savepoint: true) do
      update_review
      work_cycle_id = create_work_cycle
      link_inputs(work_cycle_id, issue_ids)
      work_cycle_id
    end
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

  def review_context
    @review_context ||= LoadReviewContext.call(review: review)
  end

  def update_review
    Database.connection[:reviews].where(id: review_id).update(state: 'worker_implementation')
  end

  def create_work_cycle
    Database.connection[:work_cycles].insert(
      created_at: Time.now,
      completed_at: nil,
      review_id: review_id,
      role: 'worker',
      action: 'implementation',
      provider: nil,
      model: nil,
      reasoning_level: nil
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
