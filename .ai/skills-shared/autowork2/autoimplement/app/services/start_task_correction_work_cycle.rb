# frozen_string_literal: true

class StartTaskCorrectionWorkCycle
  include ServiceObject

  FINAL_REVIEW_STATES = %w[super_review worker_final_review manager_review].freeze

  arguments :task_id, :review_work_cycle_id

  def call
    ensure_all_issues_decided
    issue_ids = undispatched_approved_issue_ids
    return if issue_ids.empty?

    implementation_work_cycle
    correction_step_number
    ValidateCleanGitState.call(project_path: task.fetch(:project_path))
    Database.connection.transaction(savepoint: true) do
      work_cycle_id = create_work_cycle
      link_inputs(work_cycle_id, issue_ids)
      work_cycle_id
    end
  end

  private

  def ensure_all_issues_decided
    return unless produced_issues.where(Sequel[:reported_issues][:decision] => nil).any?

    raise "Work Cycle #{review_work_cycle_id} has undecided Reported Issues"
  end

  def undispatched_approved_issue_ids
    issue_ids = produced_issues.
                where(Sequel[:reported_issues][:decision] => 'approved').
                order(Sequel[:reported_issues][:id]).
                select_map(Sequel[:reported_issues][:id])
    return [] if issue_ids.empty?

    dispatched_issue_ids = Database.connection[:work_cycle_inputs].
                           where(reported_issue_id: issue_ids).
                           select_map(:reported_issue_id)
    issue_ids - dispatched_issue_ids
  end

  def produced_issues
    @produced_issues ||= Database.connection[:reported_issues].
                         join(:work_cycle_reported_issues, reported_issue_id: :id).
                         where(Sequel[:work_cycle_reported_issues][:work_cycle_id] => review_work_cycle_id).
                         select_all(:reported_issues)
  end

  def implementation_work_cycle
    return if whole_task_correction?
    return @implementation_work_cycle if defined?(@implementation_work_cycle)

    current_review_work_cycle_id = review_work_cycle.fetch(:id)
    @implementation_work_cycle = Database.connection[:work_cycles].
                                 where(task_id: task_id, role: 'worker', action: 'implementation').
                                 exclude(completed_at: nil).
                                 where { id < current_review_work_cycle_id }.
                                 order(:id).
                                 last
    return @implementation_work_cycle unless @implementation_work_cycle.nil?

    raise "Task #{task_id} has no completed implementation Work Cycle"
  end

  def review_work_cycle
    @review_work_cycle ||= Database.connection[:work_cycles].where(id: review_work_cycle_id).first
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
      step_number: correction_step_number,
      role: 'worker',
      action: 'implementation',
      provider: nil,
      model: nil,
      reasoning_level: nil
    )
  end

  def correction_step_number
    return if whole_task_correction?

    step_number = implementation_work_cycle.fetch(:step_number)
    return step_number if step_number.is_a?(Integer) && step_number.positive?

    raise "Task #{task_id} latest authored-step implementation has no positive step number"
  end

  def whole_task_correction?
    FINAL_REVIEW_STATES.include?(task.fetch(:state))
  end

  def link_inputs(work_cycle_id, issue_ids)
    created_at = Time.now
    issue_ids.each do |issue_id|
      Database.connection[:work_cycle_inputs].insert(
        created_at: created_at,
        work_cycle_id: work_cycle_id,
        reported_issue_id: issue_id
      )
    end
  end
end
