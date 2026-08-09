# frozen_string_literal: true

require 'sequel/extensions/migration'
require_relative 'spec_helper'

RSpec.describe 'database schema' do
  let(:db) { Database.connection }
  let(:initial_schema_version) { 20_260_729_115_455 }
  let(:final_checks_schema_version) { 20_260_807_190_000 }
  let(:final_review_schema_version) { 20_260_808_120_000 }
  let(:review_task_schema_version) { 20_260_809_120_000 }

  it 'uses the shared runtime database path' do
    expect(Database.default_path).to eq(Database.root.join('db', 'autowork.db'))
  end

  it 'uses the shared runtime database override' do
    original_path = ENV.fetch('AUTOWORK_DB_PATH', nil)
    ENV['AUTOWORK_DB_PATH'] = '/tmp/custom-autowork.db'

    expect(Database.path).to eq(Pathname.new('/tmp/custom-autowork.db'))
  ensure
    ENV['AUTOWORK_DB_PATH'] = original_path
  end

  it 'creates reported issues with generated IDs and creation times' do
    expect(columns(:reported_issues)).to eq(
      %i[id created_at project_path source source_id body decision]
    )
    expect(column(:reported_issues, :id)).to include(primary_key: true, auto_increment: true)
    expect(column(:reported_issues, :created_at)).to include(allow_null: false)
  end

  it 'opens a read-only participant connection' do
    expect(Database.readonly_connection[:reported_issues].count).to eq(0)
    expect { Database.readonly_connection[:reported_issues].insert(issue_attributes) }.
      to raise_error(Sequel::DatabaseError)
  end

  it 'requires issue data' do
    %i[project_path source body].each do |name|
      expect(column(:reported_issues, name)).to include(allow_null: false)
    end
    expect(column(:reported_issues, :source_id)).to include(allow_null: true)
    expect(column(:reported_issues, :decision)).to include(allow_null: true)
    expect { db[:reported_issues].insert(issue_attributes.except(:created_at)) }.
      to raise_error(Sequel::NotNullConstraintViolation)
  end

  it 'generates IDs and keeps GitHub identity unique' do
    id = db[:reported_issues].insert(issue_attributes)

    expect(id).to be_a(Integer)
    expect(db[:reported_issues].where(id: id).get(:created_at)).to eq(issue_attributes.fetch(:created_at))
    expect { db[:reported_issues].insert(issue_attributes) }.
      to raise_error(Sequel::UniqueConstraintViolation)
  end

  it 'allows repeated local issues without source IDs' do
    attributes = issue_attributes(source: 'local', source_id: nil)

    expect { 2.times { db[:reported_issues].insert(attributes) } }.not_to raise_error
  end

  it 'allows only known sources with matching source IDs' do
    %w[email autowork work_cycle].each do |source|
      expect do
        db[:reported_issues].insert(issue_attributes(source: source, source_id: nil))
      end.to raise_error(Sequel::CheckConstraintViolation)
    end
    expect { db[:reported_issues].insert(issue_attributes(source_id: nil)) }.
      to raise_error(Sequel::CheckConstraintViolation)
    expect { db[:reported_issues].insert(issue_attributes(source: 'local')) }.
      to raise_error(Sequel::CheckConstraintViolation)

    %w[local worker reviewer manager].each_with_index do |source, index|
      expect do
        db[:reported_issues].insert(issue_attributes(source: source, source_id: nil, body: "Issue #{index}."))
      end.not_to raise_error
    end
  end

  it 'allows only known decisions' do
    expect { db[:reported_issues].insert(issue_attributes(decision: 'rejected')) }.
      to raise_error(Sequel::CheckConstraintViolation)

    expect { db[:reported_issues].insert(issue_attributes(decision: 'approved')) }.not_to raise_error
    expect { db[:reported_issues].insert(issue_attributes(source_id: '2', decision: 'skipped')) }.not_to raise_error
  end

  it 'adds the reported issue identity and queue indexes' do
    indexes = db.indexes(:reported_issues)

    expect(indexes.fetch(:reported_issues_identity_index)).to include(
      unique: true,
      columns: %i[project_path source source_id]
    )
    expect(indexes.fetch(:reported_issues_queue_index)).to include(
      unique: false,
      columns: %i[project_path source decision source_id]
    )
  end

  it 'creates Task-owned Reviews with lifecycle metadata and a distinct starting boundary' do
    expect(columns(:reviews)).to eq(
      %i[id created_at completed_at number source starting_commit_sha state task_id]
    )
    expect_generated_id_and_created_at(:reviews)

    %i[number source starting_commit_sha state task_id].each do |name|
      expect(column(:reviews, name)).to include(allow_null: false)
    end
    expect(column(:reviews, :completed_at)).to include(allow_null: true)
  end

  it 'enforces Review source, state, and Task-scoped number' do
    task_id = insert_task
    db[:reviews].insert(review_attributes(task_id: task_id))

    expect { db[:reviews].insert(review_attributes(task_id: task_id, number: 1)) }.
      to raise_error(Sequel::UniqueConstraintViolation)
    db[:reviews].where(task_id: task_id).update(state: 'completed', completed_at: timestamp)

    %w[email autowork].each do |source|
      expect { db[:reviews].insert(review_attributes(task_id: task_id, number: 2, source: source)) }.
        to raise_error(Sequel::CheckConstraintViolation)
    end
    expect { db[:reviews].insert(review_attributes(task_id: task_id, number: 2, state: 'running')) }.
      to raise_error(Sequel::CheckConstraintViolation)

    other_task_id = insert_task(task_path: '/tasks/2', project_path: '/other-project')
    expect { db[:reviews].insert(review_attributes(task_id: other_task_id)) }.not_to raise_error
  end

  it 'allows only one active Review per Task' do
    task_id = insert_task
    review_id = db[:reviews].insert(review_attributes(task_id: task_id))

    expect { db[:reviews].insert(review_attributes(task_id: task_id, number: 2)) }.
      to raise_error(Sequel::UniqueConstraintViolation)

    db[:reviews].where(id: review_id).update(state: 'completed', completed_at: timestamp)

    expect { db[:reviews].insert(review_attributes(task_id: task_id, number: 2)) }.not_to raise_error
    other_task_id = insert_task(task_path: '/tasks/2', project_path: '/other-project')
    expect { db[:reviews].insert(review_attributes(task_id: other_task_id)) }.not_to raise_error

    index_sql = db[:sqlite_master].
                where(type: 'index', name: 'reviews_one_active_per_task_index').
                get(:sql)
    expect(index_sql).to match(/CREATE UNIQUE INDEX.*task_id.*WHERE.*state.*completed/i)
  end

  it 'creates Review issue relationships with foreign keys and unique pairs' do
    expect(columns(:review_issues)).to eq(
      %i[id created_at review_id reported_issue_id]
    )
    expect_generated_id_and_created_at(:review_issues)

    task_id = insert_task
    review_id = db[:reviews].insert(review_attributes(task_id: task_id))
    issue_id = db[:reported_issues].insert(issue_attributes)
    attributes = relationship_attributes(review_id: review_id, reported_issue_id: issue_id)
    db[:review_issues].insert(attributes)

    expect { db[:review_issues].insert(attributes) }.
      to raise_error(Sequel::UniqueConstraintViolation)
    expect { db[:review_issues].insert(attributes.merge(review_id: review_id + 1)) }.
      to raise_error(Sequel::ForeignKeyConstraintViolation)
  end

  it 'creates Tasks with required identity and starting boundary' do
    expect(columns(:tasks)).to eq(
      %i[id created_at task_path project_path starting_commit_sha state super_review_agent]
    )
    expect_generated_id_and_created_at(:tasks)
    %i[task_path project_path starting_commit_sha state super_review_agent].each do |name|
      expect(column(:tasks, name)).to include(allow_null: false)
    end

    task_id = db[:tasks].insert(task_attributes)

    expect(task_id).to be_a(Integer)
    expect { db[:tasks].insert(task_attributes.except(:created_at)) }.
      to raise_error(Sequel::NotNullConstraintViolation)
  end

  it 'keeps Task paths unique and allows only known runtime states and super-review agents' do
    db[:tasks].insert(task_attributes)

    expect do
      db[:tasks].insert(task_attributes(project_path: '/other-project'))
    end.to raise_error(Sequel::UniqueConstraintViolation)
    %w[super_review worker_final_review manager_review final_checks_passed].each_with_index do |state, index|
      expect do
        db[:tasks].insert(
          task_attributes(
            task_path: "/tasks/#{index + 2}",
            project_path: "/#{state}-project",
            state: state,
            super_review_agent: index.even? ? 'claude' : 'codex'
          )
        )
      end.not_to raise_error
    end
    expect do
      db[:tasks].insert(
        task_attributes(task_path: '/tasks/6', project_path: '/running-project', state: 'running')
      )
    end.to raise_error(Sequel::CheckConstraintViolation)
    expect do
      db[:tasks].insert(
        task_attributes(
          task_path: '/tasks/7',
          project_path: '/unsupported-agent-project',
          super_review_agent: 'terra'
        )
      )
    end.to raise_error(Sequel::CheckConstraintViolation)

    expect(db.indexes(:tasks).fetch(:tasks_task_path_index)).to include(
      unique: true,
      columns: [:task_path]
    )
  end

  it 'allows only one active Task per project' do
    db[:tasks].insert(task_attributes)

    expect do
      db[:tasks].insert(task_attributes(task_path: '/tasks/2'))
    end.to raise_error(Sequel::UniqueConstraintViolation)
    expect do
      db[:tasks].insert(task_attributes(task_path: '/tasks/3', project_path: '/other-project'))
    end.not_to raise_error

    expect(db.indexes(:tasks).fetch(:tasks_one_active_per_project_index)).to include(
      unique: true,
      columns: [:project_path]
    )
  end

  it 'creates Work Cycles with exactly one nullable owner and nullable provenance' do
    expect(columns(:work_cycles)).to eq(
      %i[
        id created_at completed_at review_id task_id step_number role action provider model reasoning_level
      ]
    )
    expect_generated_id_and_created_at(:work_cycles)

    %i[role action].each do |name|
      expect(column(:work_cycles, name)).to include(allow_null: false)
    end
    %i[completed_at review_id task_id step_number provider model reasoning_level].each do |name|
      expect(column(:work_cycles, name)).to include(allow_null: true)
    end
  end

  it 'enforces Work Cycle ownership, roles, actions, and foreign keys' do
    task_id = insert_task
    review_id = db[:reviews].insert(review_attributes(task_id: task_id))
    review_work_cycle_id = db[:work_cycles].insert(work_cycle_attributes(review_id: review_id))
    task_work_cycle_id = db[:work_cycles].insert(
      work_cycle_attributes(task_id: task_id, step_number: 1)
    )

    expect(review_work_cycle_id).to be_a(Integer)
    expect(task_work_cycle_id).to be_a(Integer)
    expect do
      db[:work_cycles].insert(work_cycle_attributes)
    end.to raise_error(Sequel::CheckConstraintViolation)
    expect do
      db[:work_cycles].insert(work_cycle_attributes(review_id: review_id, task_id: task_id))
    end.to raise_error(Sequel::CheckConstraintViolation)
    expect do
      db[:work_cycles].insert(work_cycle_attributes(review_id: review_id, role: 'operator'))
    end.to raise_error(Sequel::CheckConstraintViolation)
    expect do
      db[:work_cycles].insert(work_cycle_attributes(review_id: review_id, action: 'debate'))
    end.to raise_error(Sequel::CheckConstraintViolation)
    expect do
      db[:work_cycles].insert(work_cycle_attributes(review_id: review_id + 1))
    end.to raise_error(Sequel::ForeignKeyConstraintViolation)
    expect do
      db[:work_cycles].insert(work_cycle_attributes(task_id: task_id + 1, step_number: 1))
    end.to raise_error(Sequel::ForeignKeyConstraintViolation)
  end

  it 'allows positive or whole-task scope only for Task-owned Worker implementation Work Cycles' do
    task_id = insert_task
    review_id = db[:reviews].insert(review_attributes(task_id: task_id))

    expect do
      db[:work_cycles].insert(work_cycle_attributes(task_id: task_id, step_number: 1))
    end.not_to raise_error
    expect do
      db[:work_cycles].insert(work_cycle_attributes(task_id: task_id))
    end.not_to raise_error
    expect do
      db[:work_cycles].insert(work_cycle_attributes(task_id: task_id, step_number: 0))
    end.to raise_error(Sequel::CheckConstraintViolation)
    expect do
      db[:work_cycles].insert(work_cycle_attributes(review_id: review_id, step_number: 1))
    end.to raise_error(Sequel::CheckConstraintViolation)
    expect do
      db[:work_cycles].insert(
        work_cycle_attributes(task_id: task_id, step_number: 1, action: 'review')
      )
    end.to raise_error(Sequel::CheckConstraintViolation)
    expect do
      db[:work_cycles].insert(work_cycle_attributes(task_id: task_id, action: 'review'))
    end.not_to raise_error
  end

  it 'creates Work Cycle input and reported-issue relationships with foreign keys and unique pairs' do
    %i[work_cycle_inputs work_cycle_reported_issues].each do |table|
      expect(columns(table)).to eq(%i[id created_at work_cycle_id reported_issue_id])
      expect_generated_id_and_created_at(table)
    end

    task_id = db[:tasks].insert(task_attributes)
    work_cycle_id = db[:work_cycles].insert(
      work_cycle_attributes(task_id: task_id, step_number: 1)
    )
    input_issue_id = db[:reported_issues].insert(issue_attributes)
    reported_issue_id = db[:reported_issues].insert(
      issue_attributes(source: 'reviewer', source_id: nil, body: 'Reviewer issue.')
    )
    input_attributes = relationship_attributes(
      work_cycle_id: work_cycle_id,
      reported_issue_id: input_issue_id
    )
    reported_issue_attributes = relationship_attributes(
      work_cycle_id: work_cycle_id,
      reported_issue_id: reported_issue_id
    )
    db[:work_cycle_inputs].insert(input_attributes)
    db[:work_cycle_reported_issues].insert(reported_issue_attributes)

    expect { db[:work_cycle_inputs].insert(input_attributes) }.
      to raise_error(Sequel::UniqueConstraintViolation)
    expect { db[:work_cycle_reported_issues].insert(reported_issue_attributes) }.
      to raise_error(Sequel::UniqueConstraintViolation)
    expect do
      db[:work_cycle_inputs].insert(input_attributes.merge(reported_issue_id: input_issue_id + 2))
    end.to raise_error(Sequel::ForeignKeyConstraintViolation)

    task_work_cycle_ids = db[:work_cycles].where(task_id: task_id).select_map(:id)
    expect(
      db[:work_cycle_reported_issues].
        where(work_cycle_id: task_work_cycle_ids).
        select_map(:reported_issue_id)
    ).to eq([reported_issue_id])
    expect(db.table_exists?(:task_issues)).to be(false)
  end

  it 'keeps the Task-state migration compatible with an Autofix database without Tasks' do
    Dir.mktmpdir('autofix-legacy-schema-spec') do |dir|
      legacy_db = Sequel.sqlite(File.join(dir, 'legacy.db'))

      begin
        legacy_db.create_table(:schema_migrations) do
          String :filename, primary_key: true
        end
        legacy_db[:schema_migrations].insert(filename: '20260729115455_create_reported_issues.rb')

        expect { Sequel::Migrator.run(legacy_db, migrations_path) }.not_to raise_error
        expect(legacy_db.table_exists?(:tasks)).to be(false)
        expect(legacy_db[:schema_migrations].count).to eq(5)

        expect do
          Sequel::Migrator.run(legacy_db, migrations_path, target: initial_schema_version)
        end.not_to raise_error
        expect(legacy_db[:schema_migrations].count).to eq(1)
      ensure
        legacy_db.disconnect
      end
    end
  end

  it 'preserves existing Task rows, relationships, and indexes across the state migration' do
    Dir.mktmpdir('task-state-migration-spec') do |dir|
      migration_db = Sequel.sqlite(File.join(dir, 'migration.db'))

      begin
        Database.configure_connection(migration_db)
        Sequel::Migrator.run(migration_db, migrations_path, target: initial_schema_version)
        task_id = migration_db[:tasks].insert(legacy_task_attributes)
        work_cycle_id = migration_db[:work_cycles].insert(
          work_cycle_attributes(task_id: task_id, step_number: 1)
        )

        Sequel::Migrator.run(migration_db, migrations_path, target: final_review_schema_version)

        expect(migration_db[:tasks].where(id: task_id).first).to include(
          legacy_task_attributes.merge(super_review_agent: 'claude')
        )
        expect(migration_db[:work_cycles].where(id: work_cycle_id).get(:task_id)).to eq(task_id)
        expect(migration_db.indexes(:tasks)).to include(
          tasks_task_path_index: include(unique: true, columns: [:task_path]),
          tasks_one_active_per_project_index: include(unique: true, columns: [:project_path])
        )
        final_task_id = migration_db[:tasks].insert(
          legacy_task_attributes(
            task_path: '/tasks/2',
            project_path: '/final-checks-project',
            state: 'final_checks_passed'
          )
        )
        expect do
          migration_db[:work_cycles].insert(
            work_cycle_attributes(task_id: final_task_id + 1, step_number: 1)
          )
        end.to raise_error(Sequel::ForeignKeyConstraintViolation)

        migration_db[:tasks].where(id: final_task_id).delete
        Sequel::Migrator.run(migration_db, migrations_path, target: final_checks_schema_version)

        expect(migration_db[:tasks].columns).not_to include(:super_review_agent)
        expect do
          migration_db[:work_cycles].insert(work_cycle_attributes(task_id: task_id))
        end.to raise_error(Sequel::CheckConstraintViolation)

        Sequel::Migrator.run(migration_db, migrations_path, target: initial_schema_version)

        expect(migration_db[:tasks].where(id: task_id).first).to include(legacy_task_attributes)
        expect do
          migration_db[:tasks].insert(
            legacy_task_attributes(
              task_path: '/tasks/3',
              project_path: '/rolled-back-project',
              state: 'final_checks_passed'
            )
          )
        end.to raise_error(Sequel::CheckConstraintViolation)
      ensure
        migration_db.disconnect
      end
    end
  end

  it 'removes duplicated Git metadata and restores its empty schema on rollback' do
    Dir.mktmpdir('git-metadata-migration-spec') do |dir|
      migration_db = Sequel.sqlite(File.join(dir, 'migration.db'))

      begin
        Sequel::Migrator.run(migration_db, migrations_path, target: review_task_schema_version)
        expect(migration_db[:tasks].columns).to include(:branch_name)
        expect(migration_db[:reviews].columns).to include(
          :project_path,
          :branch_name,
          :original_base_ref,
          :original_base_commit_sha,
          :active_base_ref,
          :active_base_commit_sha
        )

        Sequel::Migrator.run(migration_db, migrations_path)
        expect(migration_db[:tasks].columns).not_to include(:branch_name)
        expect(migration_db[:reviews].columns).to eq(
          %i[id created_at completed_at number source starting_commit_sha state task_id]
        )

        Sequel::Migrator.run(migration_db, migrations_path, target: review_task_schema_version)
        expect(migration_db[:tasks].columns).to include(:branch_name)
        expect(migration_db[:reviews].columns).to include(
          :project_path,
          :branch_name,
          :original_base_ref,
          :original_base_commit_sha,
          :active_base_ref,
          :active_base_commit_sha
        )
      ensure
        migration_db.disconnect
      end
    end
  end

  it 'rolls back the schema' do
    Dir.mktmpdir('autofix-schema-spec') do |dir|
      rollback_db = Sequel.sqlite(File.join(dir, 'rollback.db'))

      begin
        Database.configure_connection(rollback_db)
        Sequel::Migrator.run(rollback_db, migrations_path)
        expect(rollback_db.tables).to include(
          :reported_issues,
          :reviews,
          :review_issues,
          :tasks,
          :work_cycles,
          :work_cycle_inputs,
          :work_cycle_reported_issues
        )

        Sequel::Migrator.run(rollback_db, migrations_path, target: 0)
        expect(rollback_db.tables).not_to include(
          :reported_issues,
          :reviews,
          :review_issues,
          :tasks,
          :work_cycles,
          :work_cycle_inputs,
          :work_cycle_reported_issues
        )
      ensure
        rollback_db.disconnect
      end
    end
  end

  def columns(table)
    db.schema(table).map(&:first)
  end

  def column(table, name)
    db.schema(table).to_h.fetch(name)
  end

  def expect_generated_id_and_created_at(table)
    expect(column(table, :id)).to include(primary_key: true, auto_increment: true)
    expect(column(table, :created_at)).to include(allow_null: false)
  end

  def issue_attributes(overrides = {})
    {
      created_at: timestamp,
      project_path: '/project',
      source: 'github',
      source_id: '1',
      body: 'Fix the write order.',
      decision: nil
    }.merge(overrides)
  end

  def review_attributes(overrides = {})
    {
      created_at: timestamp,
      completed_at: nil,
      number: 1,
      source: 'github',
      starting_commit_sha: 'review-starting-sha',
      state: 'manager_issues_assessment',
      task_id: 1
    }.merge(overrides)
  end

  def insert_task(overrides = {})
    db[:tasks].insert(task_attributes(overrides))
  end

  def legacy_task_attributes(overrides = {})
    task_attributes(overrides).merge(branch_name: 'feature')
  end

  def task_attributes(overrides = {})
    {
      created_at: timestamp,
      task_path: '/tasks/1',
      project_path: '/project',
      starting_commit_sha: 'starting-sha',
      state: 'initialized'
    }.merge(overrides)
  end

  def work_cycle_attributes(overrides = {})
    {
      created_at: timestamp,
      completed_at: nil,
      review_id: nil,
      task_id: nil,
      step_number: nil,
      role: 'worker',
      action: 'implementation',
      provider: nil,
      model: nil,
      reasoning_level: nil
    }.merge(overrides)
  end

  def relationship_attributes(overrides)
    { created_at: timestamp }.merge(overrides)
  end

  def timestamp
    Time.local(2026, 7, 29, 12)
  end

  def migrations_path
    Database.root.join('db', 'migrations').to_s
  end
end
