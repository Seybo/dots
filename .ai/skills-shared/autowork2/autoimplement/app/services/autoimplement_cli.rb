# frozen_string_literal: true

class AutoimplementCli
  include ServiceObject

  arguments :cli_args

  def call
    MigrateDatabase.call
    puts handle_command
  end

  private

  def handle_command
    if cli_args.length == 2 && cli_args.first == 'initialize-task'
      task = InitializeTask.call(task_path: cli_args.fetch(1))
      return RenderTask.call(task: task)
    end

    raise ArgumentError, usage
  end

  def usage
    'Usage: autoimplement initialize-task <canonical-task-path>'
  end
end
