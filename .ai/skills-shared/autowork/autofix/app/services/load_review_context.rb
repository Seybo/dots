# frozen_string_literal: true

class LoadReviewContext
  include ServiceObject

  arguments :review

  def call
    LoadTaskContext.call(task: task).merge(review: review)
  end

  private

  def task
    @task ||= Database.connection[:tasks].where(id: review.fetch(:task_id)).first ||
              raise("No Task for Review #{review.fetch(:id)}")
  end
end
