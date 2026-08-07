# frozen_string_literal: true

Sequel.migration do
  up do
    next unless table_exists?(:tasks)

    alter_table(:tasks) do
      drop_constraint(:tasks_state_allowed)
      add_constraint(
        :tasks_state_allowed,
        state: %w[initialized final_checks_passed]
      )
    end
  end

  down do
    next unless table_exists?(:tasks)

    alter_table(:tasks) do
      drop_constraint(:tasks_state_allowed)
      add_constraint(:tasks_state_allowed, state: %w[initialized])
    end
  end
end
