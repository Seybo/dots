# frozen_string_literal: true

class StoreDecision
  include ServiceObject

  arguments :issue_id, :decision

  def call
    issue_dataset.update(decision: decision)
    issue_dataset.first
  end

  private

  def issue_dataset
    @issue_dataset ||= Database.connection[:reported_issues].where(id: issue_id)
  end
end
