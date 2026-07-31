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
    return handle_github_review if cli_args.first == 'import-github-review'
    return handle_local_review if cli_args.first == 'import-local-review'
    return handle_decision if cli_args.first == 'store-decision'
    return handle_resume if cli_args.first == 'resume'
    return show_work_cycle if cli_args.first == 'show-work-cycle'
    return wait_work_cycle if cli_args.first == 'wait-work-cycle'

    raise ArgumentError, usage
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
      'store-decision <issue-id> <decision> | resume <branch> | show-work-cycle <id> | wait-work-cycle <id>]'
  end
end
