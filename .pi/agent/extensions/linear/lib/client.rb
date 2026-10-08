# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'
require_relative 'markdown'

module Linear
  class Error < StandardError; end

  class Client
    ENDPOINT = 'https://api.linear.app/graphql'
    ISSUE_FIELDS = 'id identifier title description url branchName team { id key }'
    TYPES = %w[Bug Feature Improvement Chore].freeze
    WRITE_WARNING = 'Write outcome may be uncertain; inspect Linear before retrying. Do not blindly recreate the issue.'

    def initialize(api_key: ENV.fetch('LINEAR_API_KEY', nil))
      @api_key = api_key
    end

    def get_issue(selector)
      id = identifier(selector)
      data = request("query($id: String!) { issue(id: $id) { #{ISSUE_FIELDS} } }", { 'id' => id })
      validate_issue(data['issue'])
    end

    def identifier(selector)
      value = selector.to_s
      if value.start_with?('https://linear.app/')
        value = URI.parse(value).path.split('/').then { |parts| parts[parts.index('issue').to_i + 1] }
      end
      return value if value&.match?(/\A[A-Z][A-Z0-9]*-\d+\z/)

      raise Error, 'Use a full issue identifier (HC-123) or a linear.app issue URL'
    end

    def discover(config)
      data = request('{ viewer { id } organization { id name urlKey } }')
      unless data.fetch('organization').fetch('urlKey') == config.fetch('workspace')
        raise Error, 'Linear workspace does not match configuration'
      end

      team = exact(connection('teams', 'id name key'), config.fetch('team'), 'team')
      team_id = team.fetch('id')
      states = connection('states', 'id name type', team_id: team_id)
      state = exact(states, config.fetch('status'), 'status')
      labels = connection('labels', 'id name', team_id: team_id)
      destination = {
        'workspace' => data.fetch('organization'), 'team_id' => team_id, 'team_key' => team.fetch('key'),
        'state_id' => state.fetch('id'), 'status' => state.fetch('name'),
        'viewer_id' => data.fetch('viewer').fetch('id'),
        'labels' => TYPES.to_h { |type| [type, exact(labels, type, 'type label').fetch('id')] }
      }
      if config['project']
        project = exact(connection('projects', 'id name', team_id: team_id), config.fetch('project'), 'Project')
        destination['project_id'] = project.fetch('id')
      end
      destination
    end

    def create_issue(params, destination)
      allowed = %w[title type description description_path assignee_id]
      unless params.is_a?(Hash) && (params.keys - allowed).empty?
        raise Error,
              "create-issue only accepts #{allowed.join(', ')}"
      end
      raise Error, 'create-issue requires title' if params['title'].to_s.strip.empty?
      raise Error, "type must be #{TYPES.join(', ')}" unless TYPES.include?(params['type'])
      if params.key?('description') && params.key?('description_path')
        raise Error, 'Use description or description_path, not both'
      end

      input = {
        'title' => params.fetch('title').strip, 'teamId' => destination.fetch('team_id'),
        'stateId' => destination.fetch('state_id'),
        'assigneeId' => params['assignee_id'] || destination.fetch('viewer_id'),
        'labelIds' => [destination.fetch('labels').fetch(params.fetch('type'))]
      }
      input['projectId'] = destination['project_id'] if destination['project_id']
      input['description'] = params['description'] if params.key?('description')
      if params['description_path']
        input['description'] =
          Markdown.parse(File.read(File.expand_path(params.fetch('description_path')))).fetch('description')
      end
      mutation('issueCreate', 'IssueCreateInput!', input)
    end

    def update_issue(uuid, input)
      raise Error, 'Updates only accept title and description' unless (input.keys - %w[title description]).empty?

      mutation('issueUpdate', 'IssueUpdateInput!', input, uuid: uuid)
    end

    private

    def connection(field, fields, team_id: nil)
      nodes = []
      cursor = nil
      loop do
        arguments = 'first: 100, after: $after'
        selection = "#{field}(#{arguments}) { nodes { #{fields} } pageInfo { hasNextPage endCursor } }"
        query = if team_id
                  "query($id: String!, $after: String) { team(id: $id) { #{selection} } }"
                else
                  "query($after: String) { #{selection} }"
                end
        variables = { 'after' => cursor }
        variables['id'] = team_id if team_id
        data = request(query, variables)
        page = (team_id ? data.fetch('team') : data).fetch(field)
        nodes.concat(page.fetch('nodes'))
        break unless page.fetch('pageInfo').fetch('hasNextPage')

        cursor = page.fetch('pageInfo').fetch('endCursor')
      end
      nodes
    end

    def exact(nodes, name, kind)
      matches = nodes.select { |node| node.fetch('name') == name }
      unless matches.size == 1
        raise Error,
              "Expected exactly one Linear #{kind} named #{name.inspect}; found #{matches.size}"
      end

      matches.first
    end

    def mutation(name, input_type, input, uuid: nil)
      declaration = uuid ? '$id: String!, ' : ''
      id_argument = uuid ? 'id: $id, ' : ''
      variables = { 'input' => input }
      variables['id'] = uuid if uuid
      query = "mutation(#{declaration}$input: #{input_type}) { #{name}(#{id_argument}input: $input) " \
              "{ success issue { #{ISSUE_FIELDS} } } }"
      data = request(query, variables, is_write: true).fetch(name)
      raise Error, "Linear mutation did not confirm success. #{WRITE_WARNING}" unless data['success'] == true

      validate_issue(data['issue'])
    rescue Error, KeyError => error
      raise Error, "#{error.message} #{WRITE_WARNING}" unless error.message.include?(WRITE_WARNING)

      raise
    end

    def validate_issue(issue)
      fields = %w[id identifier title url branchName]
      unless issue.is_a?(Hash) && fields.all? { |field| issue[field].is_a?(String) && !issue[field].empty? }
        raise Error, 'Linear did not return a complete issue'
      end

      issue
    end

    def request(query, variables = {}, is_write: false)
      raise Error, 'Set LINEAR_API_KEY in your environment' if @api_key.nil? || @api_key.empty?

      uri = URI(ENDPOINT)
      request = Net::HTTP::Post.new(uri)
      request['Content-Type'] = 'application/json'
      request['Authorization'] = @api_key
      request.body = JSON.generate(query: query, variables: variables)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) do |http|
        # Net::HTTP retries idempotent methods only; POST mutations are never retried.
        http.request(request)
      end
      raise Error, "Linear API returned HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      result = JSON.parse(response.body)
      if result['errors']&.any?
        message = result.fetch('errors').map { |error| error.fetch('message', 'GraphQL error') }.join('; ')
        raise Error, "Linear GraphQL error: #{message.gsub(@api_key, '[REDACTED]')}"
      end
      result.fetch('data')
    rescue JSON::ParserError, KeyError
      raise Error, "Linear returned an invalid response. #{WRITE_WARNING if is_write}"
    rescue Timeout::Error, IOError, SystemCallError, SocketError, OpenSSL::SSL::SSLError => error
      raise Error, "Linear request failed (#{error.class}). #{WRITE_WARNING if is_write}"
    end
  end
end
