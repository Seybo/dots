# frozen_string_literal: true

class AutoimplementCli
  include ServiceObject

  READ_ONLY_COMMANDS = %w[show-task-status show-work-cycle].freeze

  arguments :cli_args

  def call
    MigrateDatabase.call unless READ_ONLY_COMMANDS.include?(cli_args.first)
    puts handle_command
  end

  private

  def handle_command
    validate_arguments
    return handle_task_command if %w[resume-task retry-task].include?(cli_args.first)
    return handle_rebase_command if %w[rebase-task continue-task-rebase].include?(cli_args.first)
    return handle_work_cycle_command if %w[show-work-cycle wait-work-cycle].include?(cli_args.first)
    return show_task_status if cli_args.first == 'show-task-status'

    handle_primary_command
  end

  def handle_primary_command
    case cli_args.first
    when 'initialize-task' then initialize_task
    when 'store-decision' then store_decision
    when 'squash-task' then squash_task
    else raise ArgumentError, usage
    end
  end

  def validate_arguments
    is_valid = case cli_args.first
               when 'initialize-task', 'rebase-task' then [2, 3].include?(cli_args.length)
               when 'store-decision', 'squash-task', 'continue-task-rebase'
                 cli_args.length == 4
               else cli_args.length == 2
               end
    raise ArgumentError, usage unless is_valid
  end

  def handle_task_command
    return ResumeTask.call(task_id: cli_args.fetch(1)) if cli_args.first == 'resume-task'

    RetryTaskWorkCycle.call(task_id: cli_args.fetch(1))
  end

  def handle_rebase_command
    return rebase_task if cli_args.first == 'rebase-task'

    continue_task_rebase
  end

  def handle_work_cycle_command
    return ShowTaskWorkCycle.call(work_cycle_id: cli_args.fetch(1)) if cli_args.first == 'show-work-cycle'

    WaitTaskWorkCycle.call(work_cycle_id: cli_args.fetch(1))
  end

  def show_task_status
    status = LoadTaskStatus.call(
      connection: Database.readonly_connection,
      task_path: cli_args.fetch(1)
    )
    RenderTaskStatus.call(status: status)
  end

  def store_decision
    HandleTaskDecision.call(
      issue_id: cli_args.fetch(1),
      decision: cli_args.fetch(2),
      reason: cli_args.fetch(3)
    )
  end

  def squash_task
    SquashTask.call(
      task_id: cli_args.fetch(1),
      project_path: cli_args.fetch(2),
      subject: cli_args.fetch(3)
    )
  end

  def rebase_task
    RebaseTask.call(
      task_path: cli_args.fetch(1),
      project_path: ResolveProjectPath.call,
      base_ref: cli_args[2]
    )
  end

  def continue_task_rebase
    ContinueTaskRebase.call(
      task_path: cli_args.fetch(1),
      project_path: ResolveProjectPath.call,
      target_base_ref: cli_args.fetch(2),
      target_base_commit_sha: cli_args.fetch(3)
    )
  end

  def initialize_task
    arguments = { task_path: cli_args.fetch(1) }
    arguments[:super_review_agent] = cli_args.fetch(2) if cli_args.length == 3
    task = InitializeTask.call(**arguments)
    RenderTask.call(task: task)
  end

  def usage
    'Usage: autoimplement [initialize-task <canonical-task-path> [claude|codex|none] | ' \
      'resume-task <task-id> | ' \
      'retry-task <task-id> | store-decision <issue-id> <decision> <reason> | ' \
      'squash-task <task-id> <canonical-project-path> <subject> | ' \
      'rebase-task <canonical-task-path> [base-ref] | ' \
      'continue-task-rebase <canonical-task-path> <target-ref> <target-sha> | ' \
      'show-task-status <canonical-task-path> | ' \
      'show-work-cycle <id> | wait-work-cycle <id>]'
  end
end
