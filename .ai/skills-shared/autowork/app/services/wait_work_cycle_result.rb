# frozen_string_literal: true

class WaitWorkCycleResult
  include ServiceObject

  arguments :work_cycle_id, :result_path

  def call
    sleep(1) until File.file?(result_path)
    raise_failed_result if result.fetch('status') == 'failed'

    result
  end

  private

  def result
    @result ||= ValidateWorkCycleResult.call(
      work_cycle_id: work_cycle_id,
      result_path: result_path
    )
  end

  def raise_failed_result
    raise "Work Cycle #{work_cycle_id} failed: #{result.fetch('error')}"
  end
end
