# frozen_string_literal: true

class StartTaskManagerReviewWorkCycle
  include ServiceObject

  arguments :task_id

  def call
    ensure_manager_state
    ensure_no_incomplete_manager_review
    ValidateCleanGitState.call(project_path: task.fetch(:project_path))
    Database.connection.transaction(savepoint: true) do
      work_cycle_id = create_work_cycle
      link_inputs(work_cycle_id)
      work_cycle_id
    end
  end

  private

  def ensure_manager_state
    return if task.fetch(:state) == 'manager_review'

    raise "Task #{task.fetch(:id)} cannot start Manager review from state #{task.fetch(:state)}"
  end

  def ensure_no_incomplete_manager_review
    return if incomplete_manager_review.nil?

    raise "Task #{task.fetch(:id)} already has incomplete Manager review " \
          "#{incomplete_manager_review.fetch(:id)}"
  end

  def incomplete_manager_review
    @incomplete_manager_review ||= work_cycles.
                                   where(
                                     task_id: task.fetch(:id),
                                     role: 'manager',
                                     action: 'review',
                                     completed_at: nil
                                   ).
                                   order(:id).
                                   last
  end

  def create_work_cycle
    work_cycles.insert(
      created_at: Time.now,
      completed_at: nil,
      review_id: nil,
      task_id: task.fetch(:id),
      step_number: nil,
      role: 'manager',
      action: 'review',
      provider: nil,
      model: nil,
      reasoning_level: nil
    )
  end

  def link_inputs(work_cycle_id)
    created_at = Time.now
    reported_issue_ids.each do |issue_id|
      Database.connection[:work_cycle_inputs].insert(
        created_at: created_at,
        work_cycle_id: work_cycle_id,
        reported_issue_id: issue_id
      )
    end
  end

  def reported_issue_ids
    @reported_issue_ids ||= Database.connection[:work_cycle_reported_issues].
                            join(:work_cycles, id: :work_cycle_id).
                            where(Sequel[:work_cycles][:task_id] => task.fetch(:id)).
                            order(
                              Sequel[:work_cycles][:id],
                              Sequel[:work_cycle_reported_issues][:id]
                            ).
                            select_map(
                              Sequel[:work_cycle_reported_issues][:reported_issue_id]
                            ).
                            uniq
  end

  def task
    @task ||= Database.connection[:tasks].where(id: task_id).first
  end

  def work_cycles
    Database.connection[:work_cycles]
  end
end
