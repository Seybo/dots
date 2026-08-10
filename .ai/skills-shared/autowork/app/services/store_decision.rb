# frozen_string_literal: true

class StoreDecision
  include ServiceObject

  arguments :issue_id, :decision, :reason

  def call
    raise ArgumentError, 'Decision reason cannot be empty' if reason.to_s.strip.empty?

    issue_dataset.update(decision: decision, decision_reason: reason)
    issue_dataset.first
  end

  private

  def issue_dataset
    @issue_dataset ||= Database.connection[:reported_issues].where(id: issue_id)
  end
end
