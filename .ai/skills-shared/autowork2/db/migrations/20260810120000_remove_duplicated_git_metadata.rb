# frozen_string_literal: true

Sequel.migration do
  up do
    next unless table_exists?(:tasks)

    alter_table(:tasks) do
      drop_column :branch_name
    end
    alter_table(:reviews) do
      drop_column :project_path
      drop_column :branch_name
      drop_column :original_base_ref
      drop_column :original_base_commit_sha
      drop_column :active_base_ref
      drop_column :active_base_commit_sha
    end
  end

  down do
    next unless table_exists?(:tasks)

    alter_table(:tasks) do
      add_column :branch_name, String, null: false
    end
    alter_table(:reviews) do
      add_column :project_path, String, null: false
      add_column :branch_name, String, null: false
      add_column :original_base_ref, String, null: false
      add_column :original_base_commit_sha, String, null: false
      add_column :active_base_ref, String, null: false
      add_column :active_base_commit_sha, String, null: false
    end
  end
end
