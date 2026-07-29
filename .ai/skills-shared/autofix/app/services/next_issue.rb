# frozen_string_literal: true

class NextIssue
  include ServiceObject

  arguments :project_path, :source, :source_ids

  def call
    Database.connection[:reported_issues].where(
      project_path: project_path,
      source: source,
      source_id: source_ids.map(&:to_s),
      decision: nil
    ).first
  end
end
