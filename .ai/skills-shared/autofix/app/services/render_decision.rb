# frozen_string_literal: true

class RenderDecision
  include ServiceObject

  arguments :decision, :next_issue

  def call
    "Decision: #{decision}\n\n#{next_issue}"
  end
end
