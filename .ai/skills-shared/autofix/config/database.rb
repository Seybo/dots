# frozen_string_literal: true

require 'fileutils'
require 'pathname'
require 'sequel'

module Database
  module_function

  def repo_root
    Pathname.new(__dir__).join('..').expand_path
  end

  def default_path
    repo_root.join('db', 'autofix.db')
  end

  def path
    Pathname.new(ENV.fetch('AUTOFIX_DB_PATH', default_path.to_s)).expand_path
  end

  def connection
    @connection ||= begin
      FileUtils.mkdir_p(path.dirname)
      Sequel.sqlite(path.to_s).tap { |db| configure_connection(db) }
    end
  end

  def disconnect
    @connection&.disconnect
    @connection = nil
  end

  def configure_connection(db)
    db.run('PRAGMA auto_vacuum = INCREMENTAL')
    db.run('PRAGMA journal_mode = DELETE')
    db.run('PRAGMA foreign_keys = ON')
    db.run('PRAGMA synchronous = NORMAL')
    db.run('PRAGMA cache_size = -8000')
    db.run('PRAGMA busy_timeout = 5000')
    db
  end
end
