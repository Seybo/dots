# frozen_string_literal: true

class AutofixCli
  include ServiceObject

  arguments :cli_args

  def call
    MigrateDatabase.call unless cli_args.first == 'show-work-cycle'
    puts handle_command
  end

  private

  def handle_command
    return handle_import_command if %w[import-github-review import-local-review].include?(cli_args.first)
    if %w[store-decision resume rebase-review continue-review-rebase squash-review].include?(cli_args.first)
      return handle_review_command
    end
    return handle_work_cycle_command if %w[show-work-cycle wait-work-cycle].include?(cli_args.first)

    raise ArgumentError, usage
  end

  def handle_import_command
    return handle_github_review if cli_args.first == 'import-github-review'

    handle_local_review
  end

  def handle_review_command
    return handle_decision if cli_args.first == 'store-decision'
    return handle_resume if cli_args.first == 'resume'
    return handle_rebase_review if cli_args.first == 'rebase-review'
    return handle_squash_review if cli_args.first == 'squash-review'

    handle_continue_review_rebase
  end

  def handle_work_cycle_command
    return show_work_cycle if cli_args.first == 'show-work-cycle'

    wait_work_cycle
  end

  def handle_github_review
    HandleGithubReview.call(json_path: cli_args.fetch(1), project_path: project_path)
  end

  def handle_local_review
    HandleLocalReview.call(json_path: cli_args.fetch(1), project_path: project_path)
  end

  def handle_decision
    HandleDecision.call(issue_id: cli_args.fetch(1), decision: cli_args.fetch(2))
  end

  def handle_resume
    ResumeReview.call(project_path: project_path, branch_name: cli_args.fetch(1))
  end

  def handle_rebase_review
    RebaseReview.call(
      project_path: project_path,
      branch_name: cli_args.fetch(1),
      base_ref: cli_args[2]
    )
  end

  def handle_continue_review_rebase
    ContinueReviewRebase.call(
      project_path: project_path,
      branch_name: cli_args.fetch(1),
      target_base_ref: cli_args.fetch(2),
      target_base_commit_sha: cli_args.fetch(3)
    )
  end

  def handle_squash_review
    SquashReview.call(review_id: cli_args.fetch(1), project_path: project_path)
  end

  def show_work_cycle
    ShowWorkCycle.call(work_cycle_id: cli_args.fetch(1))
  end

  def wait_work_cycle
    WaitWorkCycle.call(work_cycle_id: cli_args.fetch(1))
  end

  def project_path
    @project_path ||= ResolveProjectPath.call
  end

  def usage
    'Usage: autofix [import-github-review <json-path> | import-local-review <json-path> | ' \
      'store-decision <issue-id> <decision> | resume <branch> | rebase-review <branch> [<base-ref>] | ' \
      'continue-review-rebase <branch> <target-ref> <target-sha> | squash-review <review-id> | ' \
      'show-work-cycle <id> | wait-work-cycle <id>]'
  end
end
