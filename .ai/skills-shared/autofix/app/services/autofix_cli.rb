# frozen_string_literal: true

class AutofixCli
  include ServiceObject

  arguments :cli_args

  def call
    validate_args
    MigrateDatabase.call
    cli_args.empty? ? run_github : run_local
  end

  private

  def validate_args
    return if cli_args.empty?
    return if cli_args.length == 2 && cli_args.first == 'import-local'

    raise ArgumentError, 'Usage: autofix [import-local <json-path>]'
  end

  def run_github
    store_github_issues
    puts RenderIssue.call(
      body: comment&.fetch('body'),
      author: comment&.dig('user', 'login'),
      path: comment&.fetch('path'),
      line: comment&.fetch('line')
    )
  end

  def run_local
    puts ImportLocal.call(path: cli_args.fetch(1), project_path: project_path)
  end

  def store_github_issues
    comments.each do |item|
      StoreIssue.call(
        project_path: project_path,
        source: 'github',
        source_id: item.fetch('id'),
        body: item.fetch('body')
      )
    end
  end

  def comment
    return if issue.nil?

    comments.find { |item| item.fetch('id').to_s == issue.fetch(:source_id) }
  end

  def issue
    @issue ||= NextIssue.call(
      project_path: project_path,
      source: 'github',
      source_ids: comments.map { |item| item.fetch('id') }
    )
  end

  def comments
    @comments ||= FetchComments.call
  end

  def project_path
    @project_path ||= FindProjectPath.call
  end
end
