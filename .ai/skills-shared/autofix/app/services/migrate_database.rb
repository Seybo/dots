# frozen_string_literal: true

require 'sequel/extensions/migration'

class MigrateDatabase
  include ServiceObject

  def call
    Sequel::Migrator.run(Database.connection, migrations_path.to_s)
  end

  private

  def migrations_path
    Database.repo_root.join('db', 'migrations')
  end
end
