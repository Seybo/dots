# frozen_string_literal: true

class StoreWorkCycleResult
  include ServiceObject

  arguments :work_cycle_id, :project_path, :work_cycle_result

  def call
    completed_at = Time.now
    Database.connection.transaction(savepoint: true) do
      store_completion(completed_at)
      store_reported_issues(completed_at)
    end
  end

  private

  def store_completion(completed_at)
    work_cycles.where(id: work_cycle_id).update(
      completed_at: completed_at,
      provider: work_cycle_result.fetch('provider'),
      model: work_cycle_result.fetch('model'),
      reasoning_level: work_cycle_result.fetch('reasoning_level')
    )
  end

  def store_reported_issues(created_at)
    reported_issue_bodies.map do |body|
      issue_id = StoreIssue.call(
        project_path: project_path,
        source: work_cycle.fetch(:role),
        body: body
      )
      Database.connection[:work_cycle_reported_issues].insert(
        created_at: created_at,
        work_cycle_id: work_cycle_id,
        reported_issue_id: issue_id
      )
      issue_id
    end
  end

  def reported_issue_bodies
    return [] unless work_cycle.fetch(:action) == 'review'

    work_cycle_result.fetch('reported_issues')
  end

  def work_cycle
    @work_cycle ||= work_cycles.where(id: work_cycle_id).first
  end

  def work_cycles
    Database.connection[:work_cycles]
  end
end
