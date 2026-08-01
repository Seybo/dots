# frozen_string_literal: true

Sequel.migration do
  up do
    create_table(:reported_issues) do
      primary_key :id
      DateTime :created_at, null: false
      String :project_path, text: true, null: false
      String :source, null: false
      String :source_id, text: true
      String :body, text: true, null: false
      String :decision

      constraint(
        :reported_issues_source_allowed,
        source: %w[github local worker reviewer manager]
      )
      constraint(
        :reported_issues_source_id_matches_source,
        Sequel.|(
          Sequel.&({ source: 'github' }, Sequel.~(source_id: nil)),
          { source: %w[local worker reviewer manager], source_id: nil }
        )
      )
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

    create_table(:reviews) do
      primary_key :id
      DateTime :created_at, null: false
      DateTime :completed_at
      String :project_path, text: true, null: false
      Integer :number, null: false
      String :source, null: false
      String :branch_name, text: true, null: false
      String :starting_commit_sha, text: true
      String :original_base_ref, text: true, null: false
      String :original_base_commit_sha, text: true, null: false
      String :active_base_ref, text: true, null: false
      String :active_base_commit_sha, text: true, null: false
      String :state, null: false
      String :final_commit_sha, text: true

      constraint(:reviews_source_allowed, source: %w[github local])
      constraint(
        :reviews_state_allowed,
        state: %w[
          manager_issues_assessment
          worker_implementation
          worker_review
          reviewer_review
          manager_review
          manager_finalizing
          completed
        ]
      )

      index %i[project_path number],
            unique: true,
            name: :reviews_project_number_index
      index :project_path,
            unique: true,
            where: Sequel.~(state: 'completed'),
            name: :reviews_one_active_per_project_index
    end

    create_table(:review_issues) do
      primary_key :id
      DateTime :created_at, null: false
      foreign_key :review_id, :reviews, null: false
      foreign_key :reported_issue_id, :reported_issues, null: false

      index %i[review_id reported_issue_id],
            unique: true,
            name: :review_issues_identity_index
    end

    create_table(:work_cycles) do
      primary_key :id
      DateTime :created_at, null: false
      DateTime :completed_at
      foreign_key :review_id, :reviews, null: false
      String :role, null: false
      String :action, null: false
      String :provider, text: true
      String :model, text: true
      String :reasoning_level, text: true

      constraint(:work_cycles_role_allowed, role: %w[manager worker reviewer])
      constraint(:work_cycles_action_allowed, action: %w[implementation review])
    end

    create_table(:work_cycle_inputs) do
      primary_key :id
      DateTime :created_at, null: false
      foreign_key :work_cycle_id, :work_cycles, null: false
      foreign_key :reported_issue_id, :reported_issues, null: false

      index %i[work_cycle_id reported_issue_id],
            unique: true,
            name: :work_cycle_inputs_identity_index
    end

    create_table(:work_cycle_reported_issues) do
      primary_key :id
      DateTime :created_at, null: false
      foreign_key :work_cycle_id, :work_cycles, null: false
      foreign_key :reported_issue_id, :reported_issues, null: false

      index %i[work_cycle_id reported_issue_id],
            unique: true,
            name: :work_cycle_reported_issues_identity_index
    end
  end

  down do
    drop_table(:work_cycle_reported_issues)
    drop_table(:work_cycle_inputs)
    drop_table(:work_cycles)
    drop_table(:review_issues)
    drop_table(:reviews)
    drop_table(:reported_issues)
  end
end
