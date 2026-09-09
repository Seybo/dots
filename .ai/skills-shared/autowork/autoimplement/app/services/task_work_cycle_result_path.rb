# frozen_string_literal: true

class TaskWorkCycleResultPath
  include ServiceObject

  arguments :work_cycle_id

  def call
    File.join(
      ENV.fetch('AUTOWORK_RESULT_DIR'),
      "autoimplement-work-cycle-#{work_cycle_id}.json"
    )
  end
end
