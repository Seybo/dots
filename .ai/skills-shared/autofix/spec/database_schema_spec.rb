# frozen_string_literal: true

require 'sequel/extensions/migration'
require_relative 'spec_helper'

RSpec.describe 'database schema' do
  let(:db) { Database.connection }

  it 'creates reported issues with generated IDs and creation times' do
    expect(db.schema(:reported_issues).map(&:first)).to eq(
      %i[id created_at project_path source source_id body decision]
    )
    expect(column(:id)).to include(primary_key: true, auto_increment: true)
    expect(column(:created_at)).to include(allow_null: false)
  end

  it 'requires issue data' do
    %i[project_path source source_id body].each do |name|
      expect(column(name)).to include(allow_null: false)
    end
    expect(column(:decision)).to include(allow_null: true)
    expect { db[:reported_issues].insert(issue_attributes.except(:created_at)) }.
      to raise_error(Sequel::NotNullConstraintViolation)
  end

  it 'generates IDs and keeps domain identity unique' do
    id = db[:reported_issues].insert(issue_attributes)

    expect(id).to be_a(Integer)
    expect(db[:reported_issues].where(id: id).get(:created_at)).to eq(issue_attributes.fetch(:created_at))
    expect { db[:reported_issues].insert(issue_attributes) }.
      to raise_error(Sequel::UniqueConstraintViolation)
  end

  it 'allows only known sources' do
    expect { db[:reported_issues].insert(issue_attributes(source: 'email')) }.
      to raise_error(Sequel::CheckConstraintViolation)

    expect { db[:reported_issues].insert(issue_attributes(source: 'local')) }.not_to raise_error
  end

  it 'allows only known decisions' do
    expect { db[:reported_issues].insert(issue_attributes(decision: 'rejected')) }.
      to raise_error(Sequel::CheckConstraintViolation)

    expect { db[:reported_issues].insert(issue_attributes(decision: 'approved')) }.not_to raise_error
    expect { db[:reported_issues].insert(issue_attributes(source_id: '2', decision: 'skipped')) }.not_to raise_error
  end

  it 'adds the identity and queue indexes' do
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

  it 'rolls back the schema' do
    Dir.mktmpdir('autofix-schema-spec') do |dir|
      rollback_db = Sequel.sqlite(File.join(dir, 'rollback.db'))

      begin
        Database.configure_connection(rollback_db)
        Sequel::Migrator.run(rollback_db, migrations_path)
        expect(rollback_db.table_exists?(:reported_issues)).to eq(true)

        Sequel::Migrator.run(rollback_db, migrations_path, target: 0)
        expect(rollback_db.table_exists?(:reported_issues)).to eq(false)
      ensure
        rollback_db.disconnect
      end
    end
  end

  def column(name)
    db.schema(:reported_issues).to_h.fetch(name)
  end

  def issue_attributes(overrides = {})
    {
      created_at: Time.local(2026, 7, 29, 12),
      project_path: '/project',
      source: 'github',
      source_id: '1',
      body: 'Fix the write order.',
      decision: nil
    }.merge(overrides)
  end

  def migrations_path
    Database.repo_root.join('db', 'migrations').to_s
  end
end
