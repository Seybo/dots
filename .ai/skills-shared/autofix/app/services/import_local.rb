# frozen_string_literal: true

require 'json'

class ImportLocal
  include ServiceObject

  arguments :path, :project_path

  def call
    return 'No issues found.' if bodies.empty?

    store_issues
    RenderIssue.call(body: issue.fetch(:body))
  end

  private

  def store_issues
    bodies.each do |body|
      StoreIssue.call(project_path: project_path, source: 'local', body: body)
    end
  end

  def issue
    @issue ||= NextIssue.call(project_path: project_path, source: 'local')
  end

  def bodies
    @bodies ||= JSON.parse(File.read(path)).tap do |value|
      unless value.is_a?(Array) && value.all? { |body| body.is_a?(String) && !body.strip.empty? }
        raise ArgumentError, 'Local issues must be an array of non-empty strings'
      end
    end
  end
end
