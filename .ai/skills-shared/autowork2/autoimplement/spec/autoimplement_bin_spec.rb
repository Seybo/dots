# frozen_string_literal: true

require 'open3'
require 'rbconfig'
require 'tmpdir'
require_relative '../../spec/spec_helper'

RSpec.describe 'autoimplement executable' do
  let(:bin_path) { File.expand_path('../bin/autoimplement', __dir__) }
  let(:root_path) { Dir.mktmpdir('autoimplement-bin-spec') }
  let(:package_path) { File.join(root_path, 'package') }
  let(:copied_bin_path) { File.join(package_path, 'autoimplement', 'bin', 'autoimplement') }

  before do
    FileUtils.mkdir_p(File.dirname(copied_bin_path))
    FileUtils.mkdir_p(File.join(package_path, 'config'))
    FileUtils.cp(bin_path, copied_bin_path)
    File.write(
      File.join(package_path, 'config', 'boot.rb'),
      <<~RUBY
        class AutoimplementCli
          def self.call(cli_args:)
            puts ENV.fetch('AUTOWORK_DB_PATH')
          end
        end
      RUBY
    )
  end

  after do
    FileUtils.remove_entry(root_path)
  end

  it 'is executable' do
    expect(File.executable?(bin_path)).to be(true)
  end

  it 'defaults to the disposable development database before boot' do
    stdout, stderr, status = run_copied_bin('AUTOWORK_DB_PATH' => nil)

    expect(status).to be_success
    expect(stderr).to be_empty
    expect(stdout.strip).to eq(
      File.join(File.realpath(package_path), 'db', 'autoimplement-development.db')
    )
  end

  it 'preserves an explicit database override' do
    override_path = File.join(root_path, 'override.db')
    stdout, stderr, status = run_copied_bin('AUTOWORK_DB_PATH' => override_path)

    expect(status).to be_success
    expect(stderr).to be_empty
    expect(stdout.strip).to eq(override_path)
  end

  def run_copied_bin(environment)
    Open3.capture3(
      environment,
      RbConfig.ruby,
      copied_bin_path,
      'initialize-task',
      '/task'
    )
  end
end
