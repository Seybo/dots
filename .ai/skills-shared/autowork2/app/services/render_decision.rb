# frozen_string_literal: true

class RenderDecision
  include ServiceObject

  arguments :decision, :next_action

  def call
    "Decision: #{decision}\n\n#{next_action}"
  end
end
