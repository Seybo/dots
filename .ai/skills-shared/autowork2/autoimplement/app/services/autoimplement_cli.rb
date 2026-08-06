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
    raise ArgumentError, usage unless cli_args.length == 2

    case cli_args.first
    when 'initialize-task' then initialize_task
    when 'resume-task' then ResumeTask.call(task_id: cli_args.fetch(1))
    when 'show-work-cycle' then ShowTaskWorkCycle.call(work_cycle_id: cli_args.fetch(1))
    when 'wait-work-cycle' then WaitTaskWorkCycle.call(work_cycle_id: cli_args.fetch(1))
    else raise ArgumentError, usage
    end
  end

  def initialize_task
    task = InitializeTask.call(task_path: cli_args.fetch(1))
    RenderTask.call(task: task)
  end

  def usage
    'Usage: autoimplement [initialize-task <canonical-task-path> | resume-task <task-id> | ' \
      'show-work-cycle <id> | wait-work-cycle <id>]'
  end
end
