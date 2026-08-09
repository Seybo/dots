# frozen_string_literal: true

class RenderDecision
  include ServiceObject

  arguments :decision, :reason, :next_action

  def call
    "Decision: #{decision}\nReason: #{reason}\n\n#{next_action}"
  end
end
