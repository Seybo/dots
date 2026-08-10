# frozen_string_literal: true

class LoadTaskStatus
  include ServiceObject

  arguments :connection, :task_path

  def call
    {
      task_id: task_identifier,
      task_path: canonical_task_path,
      project: File.basename(File.dirname(canonical_task_path)),
      branch: task_config.fetch('branch').fetch('name'),
      task: task,
      autoimplement: autoimplement_status,
      autofix: autofix_status,
      next_action: next_action
    }
  end

  private

  def autoimplement_status
    {
      state: task&.fetch(:state),
      accepted_step_count: accepted_step_count,
      total_step_count: task_steps.length,
      pending: autoimplement_pending_item
    }
  end

  def autofix_status
    return if review.nil?

    {
      number: review.fetch(:number),
      source: review.fetch(:source),
      state: review.fetch(:state),
      pending: review_pending_item
    }
  end

  def accepted_step_count
    return 0 if task.nil?

    accepted_numbers = AcceptedTaskStepNumbers.call(connection: connection, task_id: task.fetch(:id))
    (accepted_numbers & task_steps.map { |step| step.fetch(:number) }).length
  end

  def autoimplement_pending_item
    return if task.nil?
    return @autoimplement_pending_item if defined?(@autoimplement_pending_item)

    @autoimplement_pending_item = incomplete_task_work_cycle || undecided_task_issue
  end

  def incomplete_task_work_cycle
    rows = connection[:work_cycles].
           where(task_id: task.fetch(:id), completed_at: nil).
           order(:id).
           select(:id).
           all
    if rows.length > 1
      raise "Task #{canonical_task_path} has multiple incomplete Work Cycles"
    end

    { type: 'work_cycle', id: rows.first.fetch(:id) } unless rows.empty?
  end

  def undecided_task_issue
    issue_id = connection[:reported_issues].
               join(:work_cycle_reported_issues, reported_issue_id: :id).
               join(:work_cycles, id: :work_cycle_id).
               where(
                 Sequel[:work_cycles][:task_id] => task.fetch(:id),
                 Sequel[:reported_issues][:decision] => nil
               ).
               order(Sequel[:reported_issues][:id]).
               get(Sequel[:reported_issues][:id])
    { type: 'issue', id: issue_id } unless issue_id.nil?
  end

  def review_pending_item
    return @review_pending_item if defined?(@review_pending_item)

    @review_pending_item = incomplete_review_work_cycle || undecided_review_issue
  end

  def incomplete_review_work_cycle
    rows = connection[:work_cycles].
           where(review_id: review.fetch(:id), completed_at: nil).
           order(:id).
           select(:id).
           all
    if rows.length > 1
      raise "Review #{review.fetch(:id)} has multiple incomplete Work Cycles"
    end

    { type: 'work_cycle', id: rows.first.fetch(:id) } unless rows.empty?
  end

  def undecided_review_issue
    issue_id = connection[:reported_issues].
               join(:review_issues, reported_issue_id: :id).
               where(
                 Sequel[:review_issues][:review_id] => review.fetch(:id),
                 Sequel[:reported_issues][:decision] => nil
               ).
               order(Sequel[:reported_issues][:id]).
               get(Sequel[:reported_issues][:id])
    { type: 'issue', id: issue_id } unless issue_id.nil?
  end

  def next_action
    return pending_action(autoimplement_pending_item) unless autoimplement_pending_item.nil?
    return '/autoimplement' if task.nil? || task.fetch(:state) != 'final_checks_passed'
    return 'None' unless active_review?
    return pending_action(review_pending_item) unless review_pending_item.nil?

    '/autofix'
  end

  def pending_action(pending)
    case pending.fetch(:type)
    when 'work_cycle' then "WaitWorkCycle #{pending.fetch(:id)}"
    when 'issue' then "Issue: #{pending.fetch(:id)}"
    end
  end

  def review
    return @review if defined?(@review)
    return @review = nil if task.nil?

    active_reviews = connection[:reviews].
                     where(task_id: task.fetch(:id)).
                     exclude(state: 'completed').
                     order(:id).
                     all
    if active_reviews.length > 1
      raise "Task #{canonical_task_path} has multiple active Reviews"
    end

    unless active_reviews.empty?
      if task.fetch(:state) != 'final_checks_passed'
        raise "Task #{canonical_task_path} has an active Review before completion"
      end

      return @review = active_reviews.first
    end

    @review = connection[:reviews].
              where(task_id: task.fetch(:id), state: 'completed').
              reverse_order(:number).
              first
  end

  def active_review?
    !review.nil? && review.fetch(:state) != 'completed'
  end

  def task
    return @task if defined?(@task)

    @task = connection[:tasks].where(task_path: canonical_task_path).first
  end

  def task_steps
    @task_steps ||= TaskSteps.new(task_path: canonical_task_path).all
  end

  def task_identifier
    match = File.basename(canonical_task_path).match(/\A(\d+)(?:-|\z)/)
    raise "Cannot derive Task ID from #{canonical_task_path}" if match.nil?

    match[1]
  end

  def task_config
    @task_config ||= ReadTaskConfig.call(task_path: canonical_task_path)
  end

  def canonical_task_path
    @canonical_task_path ||= ValidateTaskFiles.call(task_path: task_path)
  end
end
