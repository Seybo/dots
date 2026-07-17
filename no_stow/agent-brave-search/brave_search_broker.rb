#!/usr/bin/env ruby
# frozen_string_literal: true

require 'etc'
require 'json'
require 'net/http'
require 'open3'
require 'socket'
require 'uri'

class BraveSearchBroker
  DEFAULT_SOCKET_PATH = '/var/tmp/agent-broker/brave-search.sock'
  DEFAULT_SOCKET_GROUP = 'staff'
  DEFAULT_IDENTITY_PATH = '/usr/local/etc/agent-broker/brave-search/identity.txt'
  DEFAULT_ENCRYPTED_KEY_PATH = '/usr/local/etc/agent-broker/brave-search/brave-api-key.age'
  DEFAULT_BRAVE_ENDPOINT = 'https://api.search.brave.com/res/v1/web/search'
  DEFAULT_RAGE_BIN = '/opt/homebrew/bin/rage'

  MAX_QUERY_BYTES = 500
  DEFAULT_COUNT = 5
  MAX_COUNT = 10
  MAX_OFFSET = 50
  RATE_LIMIT_WINDOW_SECONDS = 60
  RATE_LIMIT_REQUESTS = 30

  ALLOWED_SAFESEARCH = %w[off moderate strict].freeze
  ALLOWED_FRESHNESS = %w[pd pw pm py].freeze

  def initialize(env: ENV)
    @socket_path = env.fetch('AGENT_BRAVE_SEARCH_SOCKET', DEFAULT_SOCKET_PATH)
    @socket_group = env.fetch('AGENT_BRAVE_SEARCH_SOCKET_GROUP', DEFAULT_SOCKET_GROUP)
    @identity_path = env.fetch('AGENT_BRAVE_SEARCH_IDENTITY_PATH', DEFAULT_IDENTITY_PATH)
    @encrypted_key_path = env.fetch('AGENT_BRAVE_SEARCH_ENCRYPTED_KEY_PATH', DEFAULT_ENCRYPTED_KEY_PATH)
    @brave_endpoint = env.fetch('AGENT_BRAVE_SEARCH_ENDPOINT', DEFAULT_BRAVE_ENDPOINT)
    @rage_bin = env.fetch('AGENT_BRAVE_SEARCH_RAGE_BIN', DEFAULT_RAGE_BIN)
    @request_timestamps = []
    @api_key = nil
  end

  def run
    prepare_socket
    server = UNIXServer.new(@socket_path)
    secure_socket

    trap('TERM') { cleanup_and_exit(server) }
    trap('INT') { cleanup_and_exit(server) }

    loop do
      client = server.accept
      Thread.new(client) { |connection| handle_connection(connection) }
    end
  ensure
    File.unlink(@socket_path) if @socket_path && File.socket?(@socket_path)
  end

  private

  def prepare_socket
    dir = File.dirname(@socket_path)
    Dir.mkdir(dir) unless Dir.exist?(dir)
    File.unlink(@socket_path) if File.socket?(@socket_path)
  end

  def secure_socket
    group_id = Etc.getgrnam(@socket_group).gid
    File.chown(nil, group_id, @socket_path)
    File.chmod(0o660, @socket_path)
  rescue ArgumentError
    File.chmod(0o600, @socket_path)
  end

  def cleanup_and_exit(server)
    server.close unless server.closed?
    File.unlink(@socket_path) if File.socket?(@socket_path)
    exit
  end

  def handle_connection(connection)
    line = connection.gets
    response = process_request(line)
    connection.write(JSON.generate(response))
    connection.write("\n")
  rescue StandardError => e
    connection.write(JSON.generate(error_response('internal_error', e.class.name)))
    connection.write("\n")
  ensure
    connection.close
  end

  def process_request(line)
    return error_response('empty_request', 'request must be one JSON line') if line.nil? || line.strip.empty?

    request = JSON.parse(line)
    action = request.fetch('action', 'search')

    case action
    when 'health'
      { 'ok' => true, 'service' => 'agent-brave-search' }
    when 'search'
      enforce_rate_limit
      search(request)
    else
      error_response('unknown_action', 'supported actions: search, health')
    end
  rescue JSON::ParserError
    error_response('invalid_json', 'request must be valid JSON')
  rescue KeyError, ArgumentError => e
    error_response('invalid_request', e.message)
  rescue RateLimitedError => e
    error_response('rate_limited', e.message)
  end

  def enforce_rate_limit
    now = Time.now.to_f
    @request_timestamps = @request_timestamps.select { |timestamp| timestamp > now - RATE_LIMIT_WINDOW_SECONDS }
    raise RateLimitedError, "max #{RATE_LIMIT_REQUESTS} requests per #{RATE_LIMIT_WINDOW_SECONDS}s" if @request_timestamps.length >= RATE_LIMIT_REQUESTS

    @request_timestamps << now
  end

  def search(request)
    query = normalized_query(request['query'])
    params = brave_params(request.merge('query' => query))
    uri = URI(@brave_endpoint)
    uri.query = URI.encode_www_form(params)

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    http.open_timeout = 5
    http.read_timeout = 15

    brave_request = Net::HTTP::Get.new(uri)
    brave_request['Accept'] = 'application/json'
    brave_request['User-Agent'] = 'agent-brave-search-broker/1.0'
    brave_request['X-Subscription-Token'] = api_key

    brave_response = http.request(brave_request)
    return brave_error(brave_response) unless brave_response.is_a?(Net::HTTPSuccess)

    parsed = JSON.parse(brave_response.body)
    sanitize_response(parsed)
  rescue JSON::ParserError
    error_response('bad_upstream_response', 'Brave returned non-JSON response')
  rescue DecryptError
    error_response('decrypt_failed', 'broker could not decrypt configured secret')
  rescue Errno::ENOENT, SystemCallError, Open3::Open3Error => e
    error_response('broker_io_error', e.class.name)
  rescue Timeout::Error, Net::OpenTimeout, Net::ReadTimeout
    error_response('upstream_timeout', 'Brave request timed out')
  end

  def normalized_query(value)
    query = value.to_s.strip
    raise ArgumentError, 'query is required' if query.empty?
    raise ArgumentError, "query must be <= #{MAX_QUERY_BYTES} bytes" if query.bytesize > MAX_QUERY_BYTES

    query
  end

  def brave_params(request)
    params = {
      'q' => request.fetch('query'),
      'count' => bounded_integer(request['count'], DEFAULT_COUNT, 1, MAX_COUNT),
      'offset' => bounded_integer(request['offset'], 0, 0, MAX_OFFSET)
    }

    safesearch = request.fetch('safesearch', nil).to_s
    params['safesearch'] = safesearch if ALLOWED_SAFESEARCH.include?(safesearch)

    freshness = request.fetch('freshness', nil).to_s
    params['freshness'] = freshness if ALLOWED_FRESHNESS.include?(freshness)

    country = request.fetch('country', nil).to_s
    params['country'] = country if country.match?(/\A[A-Z]{2}\z/)

    search_lang = request.fetch('search_lang', nil).to_s
    params['search_lang'] = search_lang if search_lang.match?(/\A[a-z]{2}\z/)

    params
  end

  def bounded_integer(value, default, min, max)
    integer = value.nil? ? default : Integer(value)
    raise ArgumentError, "integer must be between #{min} and #{max}" if integer < min || integer > max

    integer
  end

  def api_key
    @api_key ||= decrypt_api_key
  end

  def decrypt_api_key
    stdout, _stderr, status = Open3.capture3(@rage_bin, '-d', '-i', @identity_path, @encrypted_key_path)
    raise DecryptError, 'rage decrypt failed' unless status.success?

    key = stdout.strip
    raise ArgumentError, 'decrypted Brave API key is empty' if key.empty?

    key
  end

  def brave_error(response)
    body = response.body.to_s[0, 500]
    error_response('upstream_error', "Brave returned HTTP #{response.code}", 'upstream_body' => body)
  end

  def sanitize_response(parsed)
    web = parsed.fetch('web', {}) || {}
    results = Array(web.fetch('results', [])).map do |result|
      {
        'title' => result['title'].to_s,
        'url' => result['url'].to_s,
        'description' => result['description'].to_s,
        'age' => result['age'].to_s,
        'page_age' => result['page_age'].to_s
      }.reject { |_key, value| value.empty? }
    end

    {
      'ok' => true,
      'type' => parsed['type'],
      'results' => results,
      'discussions' => sanitize_discussions(parsed),
      'news' => sanitize_news(parsed)
    }
  end

  def sanitize_discussions(parsed)
    discussions = parsed.fetch('discussions', {}) || {}
    Array(discussions.fetch('results', [])).map do |result|
      {
        'title' => result['title'].to_s,
        'url' => result['url'].to_s,
        'description' => result['description'].to_s
      }.reject { |_key, value| value.empty? }
    end
  end

  def sanitize_news(parsed)
    news = parsed.fetch('news', {}) || {}
    Array(news.fetch('results', [])).map do |result|
      {
        'title' => result['title'].to_s,
        'url' => result['url'].to_s,
        'description' => result['description'].to_s,
        'age' => result['age'].to_s
      }.reject { |_key, value| value.empty? }
    end
  end

  def error_response(code, message, extra = {})
    { 'ok' => false, 'error' => code, 'message' => message }.merge(extra)
  end

  class RateLimitedError < StandardError; end
  class DecryptError < StandardError; end
end

BraveSearchBroker.new.run if $PROGRAM_NAME == __FILE__
