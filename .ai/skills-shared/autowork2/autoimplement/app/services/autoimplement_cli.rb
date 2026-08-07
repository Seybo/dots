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
    when 'store-decision' then store_decision
    when 'show-work-cycle' then ShowTaskWorkCycle.call(work_cycle_id: cli_args.fetch(1))
    when 'wait-work-cycle' then WaitTaskWorkCycle.call(work_cycle_id: cli_args.fetch(1))
    else raise ArgumentError, usage
    end
  end

  def validate_arguments
    argument_count = cli_args.first == 'store-decision' ? 3 : 2
    raise ArgumentError, usage unless cli_args.length == argument_count
  end

  def store_decision
    HandleTaskDecision.call(issue_id: cli_args.fetch(1), decision: cli_args.fetch(2))
  end

  def initialize_task
    task = InitializeTask.call(task_path: cli_args.fetch(1))
    RenderTask.call(task: task)
  end

  def usage
    'Usage: autoimplement [initialize-task <canonical-task-path> | resume-task <task-id> | ' \
      'store-decision <issue-id> <decision> | show-work-cycle <id> | wait-work-cycle <id>]'
  end
end
