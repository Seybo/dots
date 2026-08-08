# frozen_string_literal: true

Sequel.migration do
  up do
    next unless table_exists?(:tasks)

    alter_table(:tasks) do
      add_column :super_review_agent, String, null: false, default: 'claude'
      drop_constraint(:tasks_state_allowed)
      add_constraint(
        :tasks_final_review_lifecycle_allowed,
        Sequel.&(
          { state: %w[
            initialized
            super_review
            worker_final_review
            manager_review
            final_checks_passed
          ] },
          { super_review_agent: %w[claude codex] }
        )
      )
    end

    alter_table(:work_cycles) do
      drop_constraint(:work_cycles_exactly_one_owner)
      drop_constraint(:work_cycles_step_number_matches_task_implementation)
      drop_constraint(:work_cycles_role_allowed)
      drop_constraint(:work_cycles_action_allowed)
      add_constraint(
        :work_cycles_final_review_lifecycle_allowed,
        Sequel.&(
          Sequel.|(
            Sequel.&(Sequel.~(review_id: nil), { task_id: nil }),
            Sequel.&({ review_id: nil }, Sequel.~(task_id: nil))
          ),
          Sequel.lit(
            "((task_id IS NOT NULL AND role = 'worker' AND action = 'implementation' " \
            'AND (step_number IS NULL OR step_number > 0)) OR ' \
            "(NOT (task_id IS NOT NULL AND role = 'worker' AND action = 'implementation') " \
            'AND step_number IS NULL))'
          ),
          { role: %w[manager worker reviewer] },
          { action: %w[implementation review] }
        )
      )
    end
  end

  down do
    next unless table_exists?(:tasks)

    alter_table(:work_cycles) do
      drop_constraint(:work_cycles_final_review_lifecycle_allowed)
      add_constraint(
        :work_cycles_original_lifecycle_allowed,
        Sequel.&(
          Sequel.|(
            Sequel.&(Sequel.~(review_id: nil), { task_id: nil }),
            Sequel.&({ review_id: nil }, Sequel.~(task_id: nil))
          ),
          Sequel.lit(
            "((task_id IS NOT NULL AND role = 'worker' AND action = 'implementation' " \
            'AND step_number IS NOT NULL AND step_number > 0) OR ' \
            "(NOT (task_id IS NOT NULL AND role = 'worker' AND action = 'implementation') " \
            'AND step_number IS NULL))'
          ),
          { role: %w[manager worker reviewer] },
          { action: %w[implementation review] }
        )
      )
    end

    alter_table(:tasks) do
      drop_constraint(:tasks_final_review_lifecycle_allowed)
      drop_column :super_review_agent
      add_constraint(
        :tasks_state_allowed,
        state: %w[initialized final_checks_passed]
      )
    end
  end
end
