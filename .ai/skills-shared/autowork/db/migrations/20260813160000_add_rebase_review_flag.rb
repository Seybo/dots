# frozen_string_literal: true

Sequel.migration do
  up do
    alter_table(:tasks) do
      add_column :is_manager_review_required, TrueClass, null: false, default: false
    end
  end

  down do
    alter_table(:tasks) do
      drop_column :is_manager_review_required
    end
  end
end
