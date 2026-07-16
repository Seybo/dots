#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require_relative "../lib/shortcut_client"

module ShortcutCli
  module_function

  def run(argv)
    command = argv.shift

    case command
    when "get-story"
      story_id = require_arg(argv, "story_id")
      print_json(Shortcut::Client.new.get_story(story_id))
    when "create-story"
      payload = read_json_payload(require_arg(argv, "json_payload_or_dash"))
      print_json(Shortcut::Client.new.create_story(payload))
    when "update-story"
      story_id = require_arg(argv, "story_id")
      description_path = require_arg(argv, "description_path")
      print_json(Shortcut::Client.new.update_story_description(story_id, description_path))
    else
      warn usage
      exit 64
    end
  rescue Shortcut::Error => e
    warn JSON.generate(error: e.message, status: e.status, body: e.body)
    exit 1
  end

  def require_arg(argv, name)
    value = argv.shift
    return value unless value.nil? || value.empty?

    raise Shortcut::Error, "Missing required argument: #{name}"
  end

  def read_json_payload(value)
    raw_json = value == "-" ? $stdin.read : value
    JSON.parse(raw_json)
  rescue JSON::ParserError => e
    raise Shortcut::Error, "Invalid JSON payload: #{e.message}"
  end

  def print_json(value)
    puts JSON.pretty_generate(value)
  end

  def usage
    <<~TEXT
      Usage:
        shortcut.rb get-story STORY_ID
        shortcut.rb create-story '{"name":"Story name","epic_id":123}'
        shortcut.rb create-story '{"name":"Story name","epic_id":123,"description_path":"description.md"}'
        echo '{"name":"Story name","epic_id":123}' | shortcut.rb create-story -
        shortcut.rb update-story STORY_ID description.md

      Create story accepts name, epic_id, and optional description_path or description. Team defaults to AI Team, workflow to GTM Engine, and state to Ready for Development.
      Update story updates description from a markdown file and, when present, the Name from its # Story details section.

      Environment:
        SHORTCUT_KEY must contain your Shortcut API token.
    TEXT
  end
end

ShortcutCli.run(ARGV) if $PROGRAM_NAME == __FILE__
