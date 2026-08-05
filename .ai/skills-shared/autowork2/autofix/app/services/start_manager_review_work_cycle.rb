# frozen_string_literal: true

class StartManagerReviewWorkCycle
  include ServiceObject

  arguments :review_id

  def call
    ValidateCleanGitState.call(project_path: review.fetch(:project_path))
    Database.connection.transaction(savepoint: true) do
      work_cycle_id = create_work_cycle
      link_inputs(work_cycle_id)
      work_cycle_id
    end
  end

  private

  def review
    @review ||= Database.connection[:reviews].where(id: review_id).first
  end

  def issue_ids
    @issue_ids ||= Database.connection[:review_issues].
                   where(review_id: review_id).
                   order(:reported_issue_id).
                   select_map(:reported_issue_id)
  end

  def create_work_cycle
    Database.connection[:work_cycles].insert(
      created_at: Time.now,
      completed_at: nil,
      review_id: review_id,
      role: 'manager',
      action: 'review',
      provider: nil,
      model: nil,
      reasoning_level: nil
    )
  end

  def link_inputs(work_cycle_id)
    issue_ids.each do |issue_id|
      Database.connection[:work_cycle_inputs].insert(
        created_at: Time.now,
        work_cycle_id: work_cycle_id,
        reported_issue_id: issue_id
      )
    end
  end
end
