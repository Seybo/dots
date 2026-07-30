# frozen_string_literal: true

class NextIssue
  include ServiceObject

  arguments :project_path, :source, source_ids: nil

  def call
    dataset = Database.connection[:reported_issues].where(
      project_path: project_path,
      source: source,
      decision: nil
    )
    dataset = dataset.where(source_id: source_ids.map(&:to_s)) unless source_ids.nil?
    dataset.order(:id).first
  end
end
