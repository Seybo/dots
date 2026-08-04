# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'

default_test_db_path = File.join(Dir.tmpdir, "autowork-test-#{Process.pid}.db")
ENV['AUTOWORK_DB_PATH'] = ENV.fetch('AUTOWORK_TEST_DB_PATH', default_test_db_path)

require_relative '../config/boot'

module SpecDatabase
  module_function

  def remove_test_database
    path = Database.path.to_s
    FileUtils.rm_f([path, "#{path}-wal", "#{path}-shm"])
  end
end

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.order = :random

  Kernel.srand config.seed

  config.expect_with(:rspec) do |expectations|
    expectations.syntax = :expect
  end

  config.before(:suite) do
    Database.disconnect
    SpecDatabase.remove_test_database
    MigrateDatabase.call
  end

  config.around do |example|
    Database.connection.transaction(rollback: :always) { example.run }
  end

  config.after(:suite) do
    Database.disconnect
    SpecDatabase.remove_test_database
  end
end
