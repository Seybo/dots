# frozen_string_literal: true

class AutofixCli
  include ServiceObject

  arguments :cli_args

  def call
    validate_args
    MigrateDatabase.call
    store_issues
    puts RenderIssue.call(comment: comment)
  end

  private

  def validate_args
    raise ArgumentError, 'Autofix does not accept arguments' unless cli_args.empty?
  end

  def store_issues
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
