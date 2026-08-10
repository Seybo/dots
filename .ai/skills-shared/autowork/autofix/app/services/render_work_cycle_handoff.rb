# frozen_string_literal: true

class RenderWorkCycleHandoff
  include ServiceObject

  arguments :work_cycle_id

  def call
    role = Database.connection[:work_cycles].where(id: work_cycle_id).get(:role)
    "AutoFixCycle #{work_cycle_id}\nAutoFixRole #{role}"
  end
end
