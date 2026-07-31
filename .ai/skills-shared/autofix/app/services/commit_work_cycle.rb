# frozen_string_literal: true

require 'open3'

class CommitWorkCycle
  include ServiceObject

  arguments :work_cycle_id, :work_cycle_result

  def call
    capture!('git', '-C', project_path, 'add', '-A')
    capture!('git', '-C', project_path, 'commit', '-m', "Work cycle #{work_cycle_id}")
    commit_sha = capture!('git', '-C', project_path, 'rev-parse', 'HEAD').strip
    StoreWorkCycleCompletion.call(
      work_cycle_id: work_cycle_id,
      work_cycle_result: work_cycle_result,
      commit_sha: commit_sha
    )
    commit_sha
  end

  private

  def project_path
    return @project_path if defined?(@project_path)

    @project_path = Database.connection[:reviews].
                    join(:work_cycles, review_id: :id).
                    where(Sequel[:work_cycles][:id] => work_cycle_id).
                    get(Sequel[:reviews][:project_path])
  end

  def capture!(*command)
    stdout, stderr, status = Open3.capture3(*command)
    return stdout if status.success?

    raise "#{command.join(' ')} failed with exit #{status.exitstatus}: #{stderr.strip}"
  end
end
