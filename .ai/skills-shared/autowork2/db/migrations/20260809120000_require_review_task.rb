# frozen_string_literal: true

Sequel.migration do
  up do
    next unless table_exists?(:tasks)

    alter_table(:reviews) do
      drop_index %i[project_path number], name: :reviews_project_number_index
      drop_index :project_path, name: :reviews_one_active_per_project_index
      set_column_not_null :starting_commit_sha
      add_foreign_key :task_id, :tasks, null: false
      add_constraint(
        :reviews_lifecycle_allowed,
        Sequel.&(
          { source: %w[github local] },
          {
            state: %w[
              manager_issues_assessment
              worker_implementation
              worker_review
              reviewer_review
              manager_review
              manager_finalizing
              completed
            ]
          }
        )
      )
      add_index %i[task_id number], unique: true, name: :reviews_task_number_index
      add_index :task_id,
                unique: true,
                where: Sequel.~(state: 'completed'),
                name: :reviews_one_active_per_task_index
    end
  end

  down do
    next unless table_exists?(:tasks)

    alter_table(:reviews) do
      drop_index %i[task_id number], name: :reviews_task_number_index
      drop_index :task_id, name: :reviews_one_active_per_task_index
      drop_foreign_key :task_id
      set_column_allow_null :starting_commit_sha
      add_constraint(
        :reviews_lifecycle_allowed,
        Sequel.&(
          { source: %w[github local] },
          {
            state: %w[
              manager_issues_assessment
              worker_implementation
              worker_review
              reviewer_review
              manager_review
              manager_finalizing
              completed
            ]
          }
        )
      )
      add_index %i[project_path number], unique: true, name: :reviews_project_number_index
      add_index :project_path,
                unique: true,
                where: Sequel.~(state: 'completed'),
                name: :reviews_one_active_per_project_index
    end
  end
end
