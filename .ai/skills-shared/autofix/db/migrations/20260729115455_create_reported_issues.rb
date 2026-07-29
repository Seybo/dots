# frozen_string_literal: true

Sequel.migration do
  up do
    create_table(:reported_issues) do
      primary_key :id
      DateTime :created_at, null: false
      String :project_path, text: true, null: false
      String :source, null: false
      String :source_id, text: true, null: false
      String :body, text: true, null: false
      String :decision

      constraint(:reported_issues_source_allowed, source: %w[github local])
      constraint(
        :reported_issues_decision_allowed,
        Sequel.|({ decision: nil }, { decision: %w[approved skipped] })
      )

      index %i[project_path source source_id],
            unique: true,
            name: :reported_issues_identity_index
      index %i[project_path source decision source_id],
            name: :reported_issues_queue_index
    end
  end

  down do
    drop_table(:reported_issues)
  end
end
