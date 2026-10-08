#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../lib/client'
require_relative '../lib/markdown'
require_relative '../lib/registry'
require_relative '../lib/task'

module LinearCli
  module_function

  def run(argv, client: Linear::Client.new, registry: Linear::Registry.new)
    command = argv.shift
    result = case command
             when 'get-issue'
               client.get_issue(argument(argv, 'identifier or URL'))
             when 'discover'
               client.discover(registry.config(argument(argv, 'project')))
             when 'create-issue'
               project = argument(argv, 'project')
               raw = argument(argv, 'JSON or -')
               params = JSON.parse(raw == '-' ? $stdin.read : raw)
               client.create_issue(params, client.discover(registry.config(project)))
             when 'update-issue'
               Linear::Task.new(client: client, registry: registry).update(argument(argv, 'identifier or URL'),
                                                                           argv.shift)
             when 'import-issue'
               project = argument(argv, 'project')
               selector = argument(argv, 'identifier or URL')
               Linear::Task.new(client: client, registry: registry).import(project, selector)
             when 'convert-draft'
               project = argument(argv, 'project')
               path = argument(argv, 'task.md path')
               type = argument(argv, 'issue type')
               Linear::Task.new(client: client, registry: registry).convert(project, path, type,
                                                                            assignee_id: argv.shift)
             else
               raise Linear::Error,
                     'Usage: linear.rb get-issue ID | discover PROJECT | create-issue PROJECT JSON | ' \
                     'update-issue ID [task.md] | import-issue PROJECT ID | ' \
                     'convert-draft PROJECT task.md TYPE [ASSIGNEE_UUID]'
             end
    puts JSON.pretty_generate(result)
    result
  end

  def argument(argv, name)
    value = argv.shift
    raise Linear::Error, "Missing #{name}" if value.nil? || value.empty?

    value
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    LinearCli.run(ARGV)
  rescue Linear::Error, JSON::ParserError, KeyError, Errno::ENOENT => error
    warn JSON.generate(error: error.message)
    exit 1
  end
end
