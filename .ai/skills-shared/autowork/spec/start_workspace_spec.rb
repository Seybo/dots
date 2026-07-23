# frozen_string_literal: true

require 'fileutils'
require 'open3'
require 'rspec'
require 'tmpdir'

RSpec.describe 'start-workspace' do
  SCRIPT = File.expand_path('../../../../no_stow/bin/tmux/start-workspace', __dir__)

  around do |example|
    Dir.mktmpdir('start-workspace-spec') do |dir|
      @tmpdir = dir
      example.run
    end
  end

  def configure_project(layout_name: 'workspace')
    project = "my_test_#{Process.pid}"
    code_root = File.join(@tmpdir, 'projects', project)
    workspace = File.join(code_root, '1st')
    task_root = File.join(@tmpdir, 'tasks', project)
    registry_dir = File.join(@tmpdir, '.ai', 'skills-shared', 'components')
    config_dir = File.join(@tmpdir, 'tmuxinator')
    bootstrap_dir = File.join(@tmpdir, 'no_stow', 'bin', 'tmux', 'layouts')
    bin_dir = File.join(@tmpdir, 'bin')
    FileUtils.mkdir_p([workspace, task_root, registry_dir, config_dir, bootstrap_dir, bin_dir])
    File.write(File.join(registry_dir, 'projects.yml'), <<~YAML)
      projects:
        #{project}:
          code_root: #{code_root}
          tmux_layout: #{layout_name}
          task_provider: local
    YAML
    File.write(File.join(config_dir, "#{layout_name}.yml"), "name: #{layout_name}\n")
    File.write(File.join(bootstrap_dir, 'default.yml'), "name: default\n")
    tmuxinator = File.join(bin_dir, 'tmuxinator')
    File.write(tmuxinator, <<~SH)
      #!/bin/sh
      printf '%s\\n' "$@" > "$ARGV_LOG"
      printf '%s\\n' "$TMUXINATOR_CONFIG" > "$CONFIG_LOG"
      exit "${TMUXINATOR_STATUS:-0}"
    SH
    FileUtils.chmod('+x', tmuxinator)

    {
      project: project,
      code_root: code_root,
      workspace: workspace,
      task_root: task_root,
      config_dir: config_dir,
      bootstrap_dir: bootstrap_dir,
      argv_log: File.join(@tmpdir, 'tmuxinator-argv.log'),
      config_log: File.join(@tmpdir, 'tmuxinator-config.log'),
      env: {
        'STOW_DIR' => @tmpdir,
        'TASK_ROOT' => File.join(@tmpdir, 'tasks'),
        'TMUXINATOR_CONFIG' => config_dir,
        'ARGV_LOG' => File.join(@tmpdir, 'tmuxinator-argv.log'),
        'CONFIG_LOG' => File.join(@tmpdir, 'tmuxinator-config.log'),
        'PATH' => "#{bin_dir}:#{ENV.fetch('PATH')}"
      }
    }
  end

  def run_launcher(fixture, *args, tmuxinator_status: '0')
    env = fixture.fetch(:env).merge('TMUXINATOR_STATUS' => tmuxinator_status)
    Open3.capture3(env, SCRIPT, *args)
  end

  it 'maps a bare project to 1st and injects tmuxinator settings' do
    fixture = configure_project

    stdout, stderr, status = run_launcher(fixture, fixture.fetch(:project))

    expect(status).to be_success, "stdout=#{stdout.inspect} stderr=#{stderr.inspect}"
    expect(File.readlines(fixture.fetch(:argv_log), chomp: true)).to eq([
      'start',
      '--skip-attach',
      '--name',
      fixture.fetch(:project),
      'workspace',
      "workspace_root=#{fixture.fetch(:workspace)}",
      "task_root=#{fixture.fetch(:task_root)}"
    ])
    expect(File.read(fixture.fetch(:config_log)).strip).to eq(fixture.fetch(:config_dir))
  end

  it 'accepts a separate workspace number' do
    fixture = configure_project
    FileUtils.mkdir_p(File.join(fixture.fetch(:code_root), '2nd'))

    _stdout, stderr, status = run_launcher(fixture, '--check', fixture.fetch(:project), '2')

    expect(status).to be_success, stderr
  end

  it 'uses a provider bootstrap when the project layout is absent' do
    fixture = configure_project
    FileUtils.rm_f(File.join(fixture.fetch(:config_dir), 'workspace.yml'))

    _stdout, stderr, status = run_launcher(fixture, fixture.fetch(:project))

    expect(status).to be_success, stderr
    expect(File.readlines(fixture.fetch(:argv_log), chomp: true)).to include('default')
    expect(File.read(fixture.fetch(:config_log)).strip).to eq(fixture.fetch(:bootstrap_dir))
  end

  it 'rejects a missing project layout and bootstrap during check' do
    fixture = configure_project(layout_name: 'missing')
    FileUtils.rm_f(File.join(fixture.fetch(:config_dir), 'missing.yml'))
    FileUtils.rm_rf(fixture.fetch(:bootstrap_dir))

    _stdout, stderr, status = run_launcher(fixture, '--check', fixture.fetch(:project))

    expect(status).not_to be_success
    expect(stderr).to include('tmuxinator layout does not exist')
  end

  it 'reports tmuxinator failures' do
    fixture = configure_project

    _stdout, stderr, status = run_launcher(fixture, fixture.fetch(:project), tmuxinator_status: '7')

    expect(status).not_to be_success
    expect(stderr).to include('tmuxinator command failed')
  end
end
