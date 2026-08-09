# frozen_string_literal: true

class StoreIssue
  include ServiceObject

  arguments :project_path, :source, :body, source_id: nil

  def call
    inserted_id = upsert

    return inserted_id if source_id.nil?

    issues.where(project_path: project_path, source: source, source_id: source_id.to_s).get(:id)
  end

  private

  def upsert
    issues.
      insert_conflict(
        target: %i[project_path source source_id],
        update: { body: Sequel[:excluded][:body] },
        update_where: { Sequel[:reported_issues][:decision] => nil }
      ).
      insert(attributes)
  end

  def issues
    Database.connection[:reported_issues]
  end

  def attributes
    {
      created_at: Time.now,
      project_path: project_path,
      source: source,
      source_id: source_id&.to_s,
      body: body,
      decision: nil,
      decision_reason: nil
    }
  end
end
