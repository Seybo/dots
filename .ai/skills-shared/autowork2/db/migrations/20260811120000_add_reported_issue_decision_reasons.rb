# frozen_string_literal: true

Sequel.migration do
  up do
    next unless table_exists?(:reported_issues)

    run <<~SQL
      ALTER TABLE reported_issues
      ADD COLUMN decision_reason TEXT
      CONSTRAINT reported_issues_decision_and_reason_valid
      CHECK (
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
      )
    SQL
  end

  down do
    next unless table_exists?(:reported_issues)

    run 'ALTER TABLE reported_issues DROP COLUMN decision_reason'
  end
end
