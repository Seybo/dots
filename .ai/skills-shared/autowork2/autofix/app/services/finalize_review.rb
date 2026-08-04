# frozen_string_literal: true

require 'open3'

class FinalizeReview
  include ServiceObject

  FINAL_CHECK_COMMANDS = ['bundle exec rubocop', 'bundle exec rspec'].freeze
  PASSING_CHECK_STATUSES = %w[passed skipped].freeze

  arguments :review_id

  def call
    results = final_check_results
    output = render_results(results)
    return output unless results.all? { |result| PASSING_CHECK_STATUSES.include?(result.fetch(:status)) }

    ValidateWorkCycleGitState.call(project_path: project_path)
    ValidateReviewCommitSequence.call(review_id: review_id)
    complete_review
    "#{output}\nReview #{review.fetch(:number)} completed locally.\n" \
      "Push: not performed.\n" \
      "AutoFixSquash #{review_id}"
  end

  private

  def review
    @review ||= Database.connection[:reviews].where(id: review_id).first
  end

  def project_path
    review.fetch(:project_path)
  end

  def final_check_results
    return [{ status: 'skipped' }] unless File.file?(File.join(project_path, 'Gemfile'))

    FINAL_CHECK_COMMANDS.map do |command|
      stdout, stderr, status = Open3.capture3('bash', '-c', command, chdir: project_path)
      {
        command: command,
        status: status.success? ? 'passed' : 'failed',
        exit_status: status.exitstatus,
        stdout: stdout,
        stderr: stderr
      }
    end
  end

  def render_results(results)
    lines = ['Final checks:']
    if results.first.fetch(:status) == 'skipped'
      lines << 'Skipped: no Gemfile.'
      return lines.join("\n")
    end

    results.each do |result|
      lines << "- #{result.fetch(:command)}: #{result.fetch(:status)} (exit #{result.fetch(:exit_status)})"
    end
    return lines.join("\n") if results.all? { |result| result.fetch(:status) == 'passed' }

    results.each do |result|
      lines << "#{result.fetch(:command)} stdout:\n#{result.fetch(:stdout)}"
      lines << "#{result.fetch(:command)} stderr:\n#{result.fetch(:stderr)}"
    end
    lines.join("\n")
  end

  def complete_review
    Database.connection[:reviews].where(id: review_id).update(
      state: 'completed',
      completed_at: Time.now
    )
  end
end
