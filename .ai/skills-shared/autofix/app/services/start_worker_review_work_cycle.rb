# frozen_string_literal: true

class StartWorkerReviewWorkCycle
  include ServiceObject

  arguments :review_id

  def call
    ensure_no_worker_review
    ValidateWorkCycleGitState.call(project_path: review.fetch(:project_path))
    Database.connection.transaction(savepoint: true) do
      update_review
      work_cycle_id = create_work_cycle
      link_inputs(work_cycle_id)
      work_cycle_id
    end
  end

  private

  def review
    @review ||= Database.connection[:reviews].where(id: review_id).first
  end

  def implementation_work_cycle
    return @implementation_work_cycle if defined?(@implementation_work_cycle)

    @implementation_work_cycle = Database.connection[:work_cycles].
                                 where(review_id: review_id, role: 'worker', action: 'implementation').
                                 exclude(completed_at: nil).
                                 order(:id).
                                 last
    if @implementation_work_cycle.nil?
      raise "Review #{review.fetch(:number)} has no completed implementation Work Cycle"
    end

    @implementation_work_cycle
  end

  def input_issue_ids
    @input_issue_ids ||= Database.connection[:work_cycle_inputs].
                         where(work_cycle_id: implementation_work_cycle.fetch(:id)).
                         order(:id).
                         select_map(:reported_issue_id)
  end

  def ensure_no_worker_review
    is_existing = Database.connection[:work_cycles].where(
      review_id: review_id,
      role: 'worker',
      action: 'review'
    ).any?
    return unless is_existing

    raise "Review #{review_id} already has a Worker review Work Cycle"
  end

  def update_review
    Database.connection[:reviews].where(id: review_id).update(state: 'worker_review')
  end

  def create_work_cycle
    Database.connection[:work_cycles].insert(
      created_at: Time.now,
      completed_at: nil,
      review_id: review_id,
      role: 'worker',
      action: 'review',
      provider: nil,
      model: nil,
      reasoning_level: nil
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
