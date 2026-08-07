# frozen_string_literal: true

class FindNextTaskIssue
  include ServiceObject

  arguments :review_work_cycle_id

  def call
    Database.connection[:reported_issues].
      join(:work_cycle_reported_issues, reported_issue_id: :id).
      where(
        Sequel[:work_cycle_reported_issues][:work_cycle_id] => review_work_cycle_id,
        Sequel[:reported_issues][:decision] => nil
      ).
      select_all(:reported_issues).
      order(Sequel[:reported_issues][:id]).
      first
  end
end
