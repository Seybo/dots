# frozen_string_literal: true

class AutoimplementCli
  include ServiceObject

  arguments :cli_args

  def call
    MigrateDatabase.call unless cli_args.first == 'show-work-cycle'
    puts handle_command
  end

  private

  def handle_command
    validate_arguments
    case cli_args.first
    when 'initialize-task' then initialize_task
    when 'resume-task' then ResumeTask.call(task_id: cli_args.fetch(1))
    when 'retry-task' then RetryTaskWorkCycle.call(task_id: cli_args.fetch(1))
    when 'store-decision' then store_decision
    when 'show-work-cycle' then ShowTaskWorkCycle.call(work_cycle_id: cli_args.fetch(1))
    when 'wait-work-cycle' then WaitTaskWorkCycle.call(work_cycle_id: cli_args.fetch(1))
    else raise ArgumentError, usage
    end
  end

  def validate_arguments
    is_valid = case cli_args.first
               when 'initialize-task' then [2, 3].include?(cli_args.length)
               when 'store-decision' then cli_args.length == 3
               else cli_args.length == 2
               end
    raise ArgumentError, usage unless is_valid
  end

  def store_decision
    HandleTaskDecision.call(issue_id: cli_args.fetch(1), decision: cli_args.fetch(2))
  end

  def initialize_task
    arguments = { task_path: cli_args.fetch(1) }
    arguments[:super_review_agent] = cli_args.fetch(2) if cli_args.length == 3
    task = InitializeTask.call(**arguments)
    RenderTask.call(task: task)
  end

  def usage
    'Usage: autoimplement [initialize-task <canonical-task-path> [super-review-agent] | ' \
      'resume-task <task-id> | ' \
      'retry-task <task-id> | store-decision <issue-id> <decision> | show-work-cycle <id> | ' \
      'wait-work-cycle <id>]'
  end
end
