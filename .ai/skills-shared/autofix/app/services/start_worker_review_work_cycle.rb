# frozen_string_literal: true

class StartWorkerReviewWorkCycle
  include ServiceObject

  arguments :previous_work_cycle_id

  def call
    ValidateWorkCycleGitState.call(project_path: review.fetch(:project_path))
    Database.connection.transaction(savepoint: true) do
      work_cycle_id = create_work_cycle
      link_inputs(work_cycle_id)
      work_cycle_id
    end
  end

  private

  def previous_work_cycle
    @previous_work_cycle ||= Database.connection[:work_cycles].where(id: previous_work_cycle_id).first
  end

  def review
    @review ||= Database.connection[:reviews].where(id: previous_work_cycle.fetch(:review_id)).first
  end

  def input_issue_ids
    @input_issue_ids ||= Database.connection[:work_cycle_inputs].
                         where(work_cycle_id: previous_work_cycle_id).
                         order(:id).
                         select_map(:reported_issue_id)
  end

  def create_work_cycle
    Database.connection[:work_cycles].insert(
      created_at: Time.now,
      completed_at: nil,
      review_id: review.fetch(:id),
      previous_work_cycle_id: previous_work_cycle_id,
      role: 'worker',
      action: 'review',
      result: nil,
      provider: nil,
      model: nil,
      reasoning_level: nil,
      commit_sha: nil
    )
  end

  def link_inputs(work_cycle_id)
    input_issue_ids.each do |issue_id|
      Database.connection[:work_cycle_inputs].insert(
        created_at: Time.now,
        work_cycle_id: work_cycle_id,
        reported_issue_id: issue_id
      )
    end
  end
end
