# frozen_string_literal: true

require 'sequel/extensions/migration'
require_relative 'spec_helper'

RSpec.describe 'database schema' do
  let(:db) { Database.connection }

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

  it 'creates Reviews with required metadata and nullable lifecycle values' do
    expect(columns(:reviews)).to eq(
      %i[
        id created_at completed_at project_path number source branch_name starting_commit_sha original_base_ref
        original_base_commit_sha active_base_ref active_base_commit_sha state
      ]
    )
    expect_generated_id_and_created_at(:reviews)

    required = %i[
      project_path number source branch_name original_base_ref original_base_commit_sha active_base_ref
      active_base_commit_sha state
    ]
    required.each { |name| expect(column(:reviews, name)).to include(allow_null: false) }
    %i[completed_at starting_commit_sha].each do |name|
      expect(column(:reviews, name)).to include(allow_null: true)
    end
  end

  it 'enforces Review source, state, and project-scoped number' do
    db[:reviews].insert(review_attributes)

    expect { db[:reviews].insert(review_attributes(number: 1)) }.
      to raise_error(Sequel::UniqueConstraintViolation)
    %w[email autowork].each do |source|
      expect { db[:reviews].insert(review_attributes(number: 2, source: source)) }.
        to raise_error(Sequel::CheckConstraintViolation)
    end
    expect { db[:reviews].insert(review_attributes(number: 2, state: 'running')) }.
      to raise_error(Sequel::CheckConstraintViolation)
    expect do
      db[:reviews].insert(review_attributes(project_path: '/other-project'))
    end.not_to raise_error
  end

  it 'allows only one active Review per project' do
    review_id = db[:reviews].insert(review_attributes)

    expect { db[:reviews].insert(review_attributes(number: 2)) }.
      to raise_error(Sequel::UniqueConstraintViolation)

    db[:reviews].where(id: review_id).update(state: 'completed', completed_at: timestamp)

    expect { db[:reviews].insert(review_attributes(number: 2)) }.not_to raise_error
    expect do
      db[:reviews].insert(review_attributes(project_path: '/other-project'))
    end.not_to raise_error

    index_sql = db[:sqlite_master].
                where(type: 'index', name: 'reviews_one_active_per_project_index').
                get(:sql)
    expect(index_sql).to match(/CREATE UNIQUE INDEX.*project_path.*WHERE.*state.*completed/i)
  end

  it 'creates Review issue relationships with foreign keys and unique pairs' do
    expect(columns(:review_issues)).to eq(
      %i[id created_at review_id reported_issue_id]
    )
    expect_generated_id_and_created_at(:review_issues)

    review_id = db[:reviews].insert(review_attributes)
    issue_id = db[:reported_issues].insert(issue_attributes)
    attributes = relationship_attributes(review_id: review_id, reported_issue_id: issue_id)
    db[:review_issues].insert(attributes)

    expect { db[:review_issues].insert(attributes) }.
      to raise_error(Sequel::UniqueConstraintViolation)
    expect { db[:review_issues].insert(attributes.merge(review_id: review_id + 1)) }.
      to raise_error(Sequel::ForeignKeyConstraintViolation)
  end

  it 'creates Tasks with generated IDs and creation times' do
    expect(columns(:tasks)).to eq(%i[id created_at])
    expect_generated_id_and_created_at(:tasks)

    task_id = db[:tasks].insert(task_attributes)

    expect(task_id).to be_a(Integer)
    expect { db[:tasks].insert({}) }.to raise_error(Sequel::NotNullConstraintViolation)
  end

  it 'creates Work Cycles with exactly one nullable owner and nullable provenance' do
    expect(columns(:work_cycles)).to eq(
      %i[
        id created_at completed_at review_id task_id role action provider model reasoning_level
      ]
    )
    expect_generated_id_and_created_at(:work_cycles)

    %i[role action].each do |name|
      expect(column(:work_cycles, name)).to include(allow_null: false)
    end
    %i[completed_at review_id task_id provider model reasoning_level].each do |name|
      expect(column(:work_cycles, name)).to include(allow_null: true)
    end
  end

  it 'enforces Work Cycle ownership, roles, actions, and foreign keys' do
    review_id = db[:reviews].insert(review_attributes)
    task_id = db[:tasks].insert(task_attributes)
    review_work_cycle_id = db[:work_cycles].insert(work_cycle_attributes(review_id: review_id))
    task_work_cycle_id = db[:work_cycles].insert(work_cycle_attributes(task_id: task_id))

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
      db[:work_cycles].insert(work_cycle_attributes(task_id: task_id + 1))
    end.to raise_error(Sequel::ForeignKeyConstraintViolation)
  end

  it 'creates Work Cycle input and reported-issue relationships with foreign keys and unique pairs' do
    %i[work_cycle_inputs work_cycle_reported_issues].each do |table|
      expect(columns(table)).to eq(%i[id created_at work_cycle_id reported_issue_id])
      expect_generated_id_and_created_at(table)
    end

    task_id = db[:tasks].insert(task_attributes)
    work_cycle_id = db[:work_cycles].insert(work_cycle_attributes(task_id: task_id))
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
      project_path: '/project',
      number: 1,
      source: 'github',
      branch_name: 'feature',
      starting_commit_sha: nil,
      original_base_ref: 'origin/main',
      original_base_commit_sha: 'base-sha',
      active_base_ref: 'origin/main',
      active_base_commit_sha: 'base-sha',
      state: 'manager_issues_assessment'
    }.merge(overrides)
  end

  def task_attributes(overrides = {})
    { created_at: timestamp }.merge(overrides)
  end

  def work_cycle_attributes(overrides = {})
    {
      created_at: timestamp,
      completed_at: nil,
      review_id: nil,
      task_id: nil,
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
