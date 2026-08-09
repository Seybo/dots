# frozen_string_literal: true

class RebaseAutofixTask
  include ServiceObject

  arguments :task_path, :project_path, base_ref: nil

  def call
    preparation = PrepareAutofixRebase.call(
      task_path: task_path,
      project_path: project_path,
      base_ref: base_ref
    )
    status = RunGitRebase.call(preparation: preparation.fetch(:git_preparation))
    return conflict_control(preparation) if status == :conflict

    CompleteAutofixRebase.call(preparation: preparation)
  end

  private

  def conflict_control(preparation)
    "AutoFixRebaseConflict #{preparation.fetch(:task_id)}\n" \
      "RebaseTargetRef #{preparation.fetch(:target_base_ref)}\n" \
      "RebaseTargetCommit #{preparation.fetch(:target_base_commit_sha)}"
  end
end
