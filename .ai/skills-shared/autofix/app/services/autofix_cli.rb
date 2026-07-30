# frozen_string_literal: true

class AutofixCli
  include ServiceObject

  arguments :cli_args

  def call
    MigrateDatabase.call
    puts output
  end

  private

  def output
    return github_output if cli_args.empty?
    return ImportLocal.call(path: cli_args.fetch(1), project_path: project_path) if cli_args.first == 'import-local'
    return decision_output if cli_args.first == 'store-decision'

    raise ArgumentError, 'Usage: autofix [import-local <json-path> | store-decision <issue-id> <decision>]'
  end

  def github_output
    store_github_issues(project_path)
    render_issue(next_issue(project_path: project_path, source: 'github'))
  end

  def decision_output
    decision = cli_args.fetch(2)
    issue = StoreDecision.call(issue_id: cli_args.fetch(1), decision: decision)
    store_github_issues(issue.fetch(:project_path)) if issue.fetch(:source) == 'github'
    rendered_issue = render_issue(next_issue(project_path: issue.fetch(:project_path), source: issue.fetch(:source)))

    RenderDecision.call(decision: decision, next_issue: rendered_issue)
  end

  def next_issue(project_path:, source:)
    NextIssue.call(
      project_path: project_path,
      source: source,
      source_ids: source == 'github' ? comments.map { |item| item.fetch('id') } : nil
    )
  end

  def render_issue(issue)
    return RenderIssue.call(issue: nil) if issue.nil?
    return RenderIssue.call(issue: issue) if issue.fetch(:source) == 'local'

    comment = comments.find { |item| item.fetch('id').to_s == issue.fetch(:source_id) }
    RenderIssue.call(
      issue: issue,
      author: comment.fetch('user').fetch('login'),
      path: comment.fetch('path'),
      line: comment.fetch('line')
    )
  end

  def store_github_issues(project_path)
    comments.each do |item|
      StoreIssue.call(
        project_path: project_path,
        source: 'github',
        source_id: item.fetch('id'),
        body: item.fetch('body')
      )
    end
  end

  def comments
    @comments ||= FetchComments.call
  end

  def project_path
    @project_path ||= FindProjectPath.call
  end
end
