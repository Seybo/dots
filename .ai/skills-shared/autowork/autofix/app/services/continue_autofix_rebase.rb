# frozen_string_literal: true

class ContinueAutofixRebase
  include ServiceObject

  arguments :task_path, :project_path, :target_base_ref, :target_base_commit_sha

  def call
    result = ContinueGitRebase.call(
      project_path: context.fetch(:project_path),
      branch_name: context.fetch(:branch_name),
      active_base_ref: branch.fetch('active_base_ref'),
      active_base_commit_sha: branch.fetch('active_base_commit_sha'),
      boundaries: context.fetch(:boundaries),
      target_base_ref: target_base_ref,
      target_base_commit_sha: target_base_commit_sha
    )
    preparation = build_preparation(result.fetch(:preparation))
    return conflict_control(preparation) if result.fetch(:status) == :conflict

    CompleteAutofixRebase.call(preparation: preparation)
  end

  private

  def build_preparation(git_preparation)
    review = context.fetch(:review)
    {
      task_id: task.fetch(:id),
      task_path: context.fetch(:task_path),
      task_starting_commit_sha: task.fetch(:starting_commit_sha),
      review_id: review&.fetch(:id),
      review_number: review&.fetch(:number),
      review_starting_commit_sha: review&.fetch(:starting_commit_sha),
      project_path: context.fetch(:project_path),
      branch_name: context.fetch(:branch_name),
      original_base_ref: branch.fetch('original_base_ref'),
      original_base_commit_sha: branch.fetch('original_base_commit_sha'),
      active_base_ref: branch.fetch('active_base_ref'),
      active_base_commit_sha: branch.fetch('active_base_commit_sha'),
      target_base_ref: target_base_ref,
      target_base_commit_sha: target_base_commit_sha,
      git_preparation: git_preparation
    }
  end

  def conflict_control(preparation)
    "AutoFixRebaseConflict #{preparation.fetch(:task_id)}\n" \
      "RebaseTargetRef #{target_base_ref}\n" \
      "RebaseTargetCommit #{target_base_commit_sha}"
  end

  def context
    @context ||= LoadAutofixRebaseContext.call(task_path: task_path, project_path: project_path)
  end

  def task
    context.fetch(:task)
  end

  def branch
    @branch ||= context.fetch(:config).fetch('branch')
  end
end
