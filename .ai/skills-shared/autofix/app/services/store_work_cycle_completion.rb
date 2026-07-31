# frozen_string_literal: true

class StoreWorkCycleCompletion
  include ServiceObject

  arguments :work_cycle_id, :work_cycle_result, commit_sha: nil

  def call
    completed_at = Time.now
    Database.connection.transaction(savepoint: true) do
      Database.connection[:work_cycles].where(id: work_cycle_id).update(
        completed_at: completed_at,
        result: work_cycle_result.fetch('status'),
        provider: work_cycle_result.fetch('provider'),
        model: work_cycle_result.fetch('model'),
        reasoning_level: work_cycle_result.fetch('reasoning_level'),
        commit_sha: commit_sha
      )
      Database.connection[:reviews].where(id: work_cycle.fetch(:review_id)).update(state: next_review_state)
    end
  end

  private

  def work_cycle
    @work_cycle ||= Database.connection[:work_cycles].where(id: work_cycle_id).first
  end

  def next_review_state
    case [work_cycle.fetch(:role), work_cycle.fetch(:action)]
    when %w[worker implementation] then 'worker_review'
    when %w[worker review] then 'reviewer_review'
    when %w[reviewer review] then 'manager_review'
    when %w[manager review] then 'manager_finalizing'
    else
      raise "Unsupported Work Cycle completion: #{work_cycle.fetch(:role)}/#{work_cycle.fetch(:action)}"
    end
  end
end
