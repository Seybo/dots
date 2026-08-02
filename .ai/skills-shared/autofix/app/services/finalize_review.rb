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
    validate_commit_sequence
    final_commit_sha = squash
    complete_review(final_commit_sha)
    "#{output}\nReview #{review.fetch(:number)} completed locally.\n" \
      "Final commit: #{final_commit_sha} Review #{review.fetch(:number)}\n" \
      'Push: not performed.'
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

  def validate_commit_sequence
    actual_subjects = capture!(
      'git', '-C', project_path, 'log', '--reverse', '--format=%s',
      "#{review.fetch(:starting_commit_sha)}..HEAD"
    ).lines(chomp: true)
    return if actual_subjects == expected_subjects

    raise "Review #{review.fetch(:number)} commit sequence does not match its implementation Work Cycles"
  end

  def expected_subjects
    Database.connection[:work_cycles].
      where(review_id: review_id, role: 'worker', action: 'implementation').
      exclude(completed_at: nil).
      order(:id).
      select_map(:id).
      map { |work_cycle_id| "Work cycle #{work_cycle_id}" }
  end

  def squash
    capture!('git', '-C', project_path, 'reset', '--soft', review.fetch(:starting_commit_sha))
    capture!('git', '-C', project_path, 'commit', '-m', "Review #{review.fetch(:number)}")
    capture!('git', '-C', project_path, 'rev-parse', 'HEAD').strip
  end

  def complete_review(final_commit_sha)
    Database.connection[:reviews].where(id: review_id).update(
      state: 'completed',
      final_commit_sha: final_commit_sha,
      completed_at: Time.now
    )
  end

  def capture!(*command)
    stdout, stderr, status = Open3.capture3(*command)
    return stdout if status.success?

    raise "#{command.join(' ')} failed with exit #{status.exitstatus}: #{stderr.strip}"
  end
end
