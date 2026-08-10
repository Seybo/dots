# frozen_string_literal: true

class RetryTaskWorkCycle
  include ServiceObject

  INVALID_RESULT_ERRORS = [JSON::ParserError, KeyError, NoMethodError, TypeError, RuntimeError].freeze

  arguments :task_id

  def call
    work_cycle
    validate_clean_git
    remove_retryable_result
    "AutoImplementCycle #{work_cycle.fetch(:id)}"
  end

  private

  def task
    @task ||= Database.connection[:tasks].where(id: task_id).first
    return @task unless @task.nil?

    raise "Task #{task_id} does not exist"
  end

  def work_cycle
    return @work_cycle if defined?(@work_cycle)

    incomplete_work_cycles = Database.connection[:work_cycles].
                             where(task_id: task.fetch(:id), completed_at: nil).
                             order(:id).
                             all
    @work_cycle = case incomplete_work_cycles.length
                  when 1 then incomplete_work_cycles.first
                  when 0 then raise "Task #{task.fetch(:id)} has no incomplete Work Cycle to retry"
                  else
                    raise "Task #{task.fetch(:id)} has #{incomplete_work_cycles.length} incomplete Work Cycles; " \
                          'handle this state ad hoc'
                  end
  end

  def validate_clean_git
    ValidateCleanGitState.call(project_path: task.fetch(:project_path))
  rescue => err
    raise_retry_error(
      'Git validation',
      err,
      'Manually discard all Git-reported changes, then invoke Autoimplement with --retry again.'
    )
  end

  def remove_retryable_result
    return unless File.file?(result_path)

    result = validate_result
    if result && result.fetch('status') == 'completed'
      raise "Task #{task.fetch(:id)} Work Cycle #{work_cycle.fetch(:id)} has a valid completed result; " \
            'resume it normally'
    end

    delete_result
  end

  def delete_result
    File.delete(result_path)
  rescue => err
    raise_retry_error(
      'transport cleanup',
      err,
      'Keep the Work Cycle incomplete and use ad-hoc Manager handling before invoking --retry again.',
      path: result_path
    )
  end

  def validate_result
    ValidateWorkCycleResult.call(
      work_cycle_id: work_cycle.fetch(:id),
      result_path: result_path
    )
  rescue *INVALID_RESULT_ERRORS
    nil
  end

  def raise_retry_error(boundary, error, guidance, path: nil)
    location = path.nil? ? '' : " at #{path}"
    detail = error.message.to_s.lines.first.to_s.strip
    raise "Task #{task.fetch(:id)} Work Cycle #{work_cycle.fetch(:id)} retry #{boundary} failed#{location}: " \
          "#{detail}. #{guidance}"
  end

  def result_path
    @result_path ||= TaskWorkCycleResultPath.call(work_cycle_id: work_cycle.fetch(:id))
  end
end
