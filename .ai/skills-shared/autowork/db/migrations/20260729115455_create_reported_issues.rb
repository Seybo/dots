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
      String :decision_reason, text: true

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
        :reported_issues_decision_and_reason_valid,
        Sequel.lit(<<~SQL)
          (decision IS NULL AND decision_reason IS NULL) OR
          (
            decision IS NOT NULL AND
            decision IN ('approved', 'skipped') AND
            decision_reason IS NOT NULL AND
            length(
              trim(
                decision_reason,
                char(9) || char(10) || char(11) || char(12) || char(13) || ' '
              )
            ) > 0
          )
        SQL
      )

      index %i[project_path source source_id],
            unique: true,
            name: :reported_issues_identity_index
      index %i[project_path source decision source_id],
            name: :reported_issues_queue_index
    end

    create_table(:tasks) do
      primary_key :id
      DateTime :created_at, null: false
      String :task_path, text: true, null: false
      String :project_path, text: true, null: false
      String :starting_commit_sha, text: true, null: false
      String :state, null: false
      String :super_review_agent, null: false, default: 'claude'

      constraint(
        :tasks_final_review_lifecycle_allowed,
        Sequel.&(
          {
            state: %w[
              initialized
              super_review
              worker_final_review
              manager_review
              final_checks_passed
            ]
          },
          { super_review_agent: %w[claude codex] }
        )
      )

      index :task_path,
            unique: true,
            name: :tasks_task_path_index
      index :project_path,
            unique: true,
            where: Sequel.~(state: 'final_checks_passed'),
            name: :tasks_one_active_per_project_index
    end

    create_table(:reviews) do
      primary_key :id
      DateTime :created_at, null: false
      DateTime :completed_at
      Integer :number, null: false
      String :source, null: false
      String :starting_commit_sha, text: true, null: false
      String :state, null: false
      foreign_key :task_id, :tasks, null: false

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

      index %i[task_id number],
            unique: true,
            name: :reviews_task_number_index
      index :task_id,
            unique: true,
            where: Sequel.~(state: 'completed'),
            name: :reviews_one_active_per_task_index
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
      foreign_key :review_id, :reviews
      foreign_key :task_id, :tasks
      Integer :step_number
      String :role, null: false
      String :action, null: false
      String :provider, text: true
      String :model, text: true
      String :reasoning_level, text: true

      constraint(
        :work_cycles_exactly_one_owner,
        Sequel.|(
          Sequel.&(Sequel.~(review_id: nil), { task_id: nil }),
          Sequel.&({ review_id: nil }, Sequel.~(task_id: nil))
        )
      )
      constraint(
        :work_cycles_step_number_matches_task_implementation,
        Sequel.lit(
          "((task_id IS NOT NULL AND role = 'worker' AND action = 'implementation' " \
          'AND (step_number IS NULL OR step_number > 0)) OR ' \
          "(NOT (task_id IS NOT NULL AND role = 'worker' AND action = 'implementation') " \
          'AND step_number IS NULL))'
        )
      )
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
    drop_table(:tasks)
    drop_table(:reported_issues)
  end
end
