# frozen_string_literal: true

class FindNextReviewIssue
  include ServiceObject

  arguments :review_id

  def call
    Database.connection[:reported_issues].
      join(:review_issues, reported_issue_id: :id).
      where(
        Sequel[:review_issues][:review_id] => review_id,
        Sequel[:reported_issues][:decision] => nil
      ).
      select_all(:reported_issues).
      order(Sequel[:reported_issues][:id]).
      first
  end
end
