# frozen_string_literal: true

Sequel.migration do
  up do
    alter_table(:tasks) do
      drop_index :project_path, name: :tasks_one_active_per_project_index
      drop_constraint :tasks_final_review_lifecycle_allowed
      set_column_default :super_review_agent, nil
      add_constraint(
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
          { super_review_agent: %w[claude codex none] }
        )
      )
      add_index :project_path,
                unique: true,
                where: Sequel.~(state: 'final_checks_passed'),
                name: :tasks_one_active_per_project_index
    end
  end

  down do
    alter_table(:tasks) do
      drop_index :project_path, name: :tasks_one_active_per_project_index
      drop_constraint :tasks_final_review_lifecycle_allowed
      set_column_default :super_review_agent, 'claude'
      add_constraint(
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
      add_index :project_path,
                unique: true,
                where: Sequel.~(state: 'final_checks_passed'),
                name: :tasks_one_active_per_project_index
    end
  end
end
