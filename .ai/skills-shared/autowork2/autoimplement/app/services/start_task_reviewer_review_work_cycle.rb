# frozen_string_literal: true

class StartTaskReviewerReviewWorkCycle
  include ServiceObject

  arguments :task_id

  def call
    implementation_work_cycle
    ValidateCleanGitState.call(project_path: task.fetch(:project_path))
    Database.connection.transaction(savepoint: true) do
      work_cycle_id = create_work_cycle
      link_inputs(work_cycle_id)
      work_cycle_id
    end
  end

  private

  def implementation_work_cycle
    return @implementation_work_cycle if defined?(@implementation_work_cycle)

    @implementation_work_cycle = Database.connection[:work_cycles].
                                 where(task_id: task_id, role: 'worker', action: 'implementation').
                                 exclude(completed_at: nil).
                                 order(:id).
                                 last
    return @implementation_work_cycle unless @implementation_work_cycle.nil?

    raise "Task #{task_id} has no completed implementation Work Cycle"
  end

  def task
    @task ||= Database.connection[:tasks].where(id: task_id).first
  end

  def create_work_cycle
    Database.connection[:work_cycles].insert(
      created_at: Time.now,
      completed_at: nil,
      review_id: nil,
      task_id: task_id,
      step_number: nil,
      role: 'reviewer',
      action: 'review',
      provider: nil,
      model: nil,
      reasoning_level: nil
    )
  end

  def link_inputs(work_cycle_id)
    Database.connection[:work_cycle_inputs].
      where(work_cycle_id: implementation_work_cycle.fetch(:id)).
      order(:id).
      select_map(:reported_issue_id).
      each do |issue_id|
        Database.connection[:work_cycle_inputs].insert(
          created_at: Time.now,
          work_cycle_id: work_cycle_id,
          reported_issue_id: issue_id
        )
      end
  end
end
