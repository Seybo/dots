# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Shortcut
  class Error < StandardError
    attr_reader :status, :body

    def initialize(message, status: nil, body: nil)
      super(message)
      @status = status
      @body = body
    end
  end

  class Client
    API_BASE_URL = "https://api.app.shortcut.com/api/v3"
    DEFAULT_GROUP_ID = "69d7e322-a521-4100-a632-a952962ce509"
    DEFAULT_WORKFLOW_STATE_ID = 500027065

    def initialize(api_key: ENV.fetch("SHORTCUT_KEY", nil))
      @api_key = api_key
    end

    def get_story(story_id)
      request(:get, "/stories/#{Integer(story_id)}")
    rescue ArgumentError
      raise Error, "story_id must be an integer"
    end

    def create_story(params)
      params = validate_create_story_params(params)
      validate_epic_exists(params.fetch("epic_id"))
      params["group_id"] = DEFAULT_GROUP_ID
      params["workflow_state_id"] = DEFAULT_WORKFLOW_STATE_ID

      request(:post, "/stories", body: params)
    end

    def update_story_description(story_id, description_path)
      story_id = Integer(story_id)
      markdown = File.read(expanded_description_path(description_path))
      story_update = story_update_from_markdown(markdown)

      request(:put, "/stories/#{story_id}", body: story_update)
    rescue ArgumentError
      raise Error, "story_id must be an integer"
    end

    private

    attr_reader :api_key

    def request(method, path, body: nil)
      raise Error, "Shortcut is not configured. Set SHORTCUT_KEY in your environment." if api_key.nil? || api_key.empty?

      uri = URI.join("#{API_BASE_URL}/", path.delete_prefix("/"))
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
        http.request(build_request(method, uri, body: body))
      end

      parse_response(response)
    end

    def build_request(method, uri, body: nil)
      request_class = case method
                      when :get then Net::HTTP::Get
                      when :post then Net::HTTP::Post
                      when :put then Net::HTTP::Put
                      else
                        raise Error, "Unsupported Shortcut HTTP method: #{method}"
                      end

      request_class.new(uri).tap do |request|
        request["Content-Type"] = "application/json"
        request["Shortcut-Token"] = api_key
        request.body = JSON.generate(body) unless body.nil?
      end
    end

    def validate_epic_exists(epic_id)
      request(:get, "/epics/#{epic_id}")
    rescue Error => e
      raise unless e.status == 404

      raise Error, "epic_id #{epic_id} was not found. Use the numeric ID from a Shortcut epic, not a story."
    end

    def validate_create_story_params(params)
      raise Error, "create-story payload must be a JSON object" unless params.is_a?(Hash)

      allowed_keys = %w[name epic_id description description_path]
      unknown_keys = params.keys - allowed_keys
      raise Error, "create-story only accepts these fields: #{allowed_keys.join(", ")}" if unknown_keys.any?
      raise Error, "create-story accepts description or description_path, not both" if params.key?("description") && params.key?("description_path")

      name = params["name"].to_s.strip
      raise Error, "create-story requires name" if name.empty?

      epic_id = params["epic_id"]
      raise Error, "create-story requires epic_id" if epic_id.nil?

      payload = {
        "name" => name,
        "epic_id" => Integer(epic_id),
      }

      description = story_description(params)
      payload["description"] = description unless description.nil?

      payload
    rescue ArgumentError
      raise Error, "epic_id must be an integer"
    end

    def story_description(params)
      return params["description"].to_s if params.key?("description")
      return nil unless params.key?("description_path")

      File.read(expanded_description_path(params["description_path"]))
    end

    def story_update_from_markdown(markdown)
      details = story_details(markdown)
      description = details ? markdown_without_story_details(markdown, details.fetch(:range)) : markdown
      body = { "description" => ensure_trailing_newline(description) }
      body["name"] = details.fetch(:name) if details&.fetch(:name, nil)
      body
    end

    def story_details(markdown)
      lines = markdown.split(/\r?\n/, -1)
      start_index = lines.index("# Story details")
      return nil unless start_index

      end_index = lines.length
      ((start_index + 1)...lines.length).each do |index|
        if lines[index].start_with?("# ")
          end_index = index
          break
        end
      end

      name = nil
      lines[(start_index + 1)...end_index].each do |line|
        next unless line.start_with?("Name:")

        value = line.delete_prefix("Name:").strip
        name = value unless value.empty?
        break
      end

      { name: name, range: start_index...end_index }
    end

    def markdown_without_story_details(markdown, range)
      lines = markdown.split(/\r?\n/, -1)
      ([*lines[0...range.begin], *lines[range.end..]]).join("\n").sub(/\A\n+/, "")
    end

    def ensure_trailing_newline(value)
      value.end_with?("\n") ? value : "#{value}\n"
    end

    def expanded_description_path(description_path)
      path = File.expand_path(description_path.to_s, Dir.pwd)
      raise Error, "description_path does not exist: #{description_path}" unless File.file?(path)

      path
    end

    def parse_response(response)
      body = response.body.to_s
      parsed_body = body.empty? ? nil : JSON.parse(body)

      return parsed_body if response.is_a?(Net::HTTPSuccess)

      message = if parsed_body.is_a?(Hash)
                  parsed_body["message"] || parsed_body["error"] || body
                else
                  body
                end

      raise Error.new("Shortcut API error: HTTP #{response.code} #{message}", status: response.code.to_i, body: parsed_body)
    rescue JSON::ParserError
      raise Error.new("Shortcut API returned invalid JSON: HTTP #{response.code}", status: response.code.to_i, body: body)
    end
  end
end
