# frozen_string_literal: true

module Coordinator::Write
  module Events
    class AgentChoiceImpactSourceLinkedV1 < Base
      contract type: "AgentChoiceImpactSourceLinked", version: 1

      attribute :assessment_id, Types::UuidV7
      attribute :role, Types::String.enum("accepted_choice", "decision_change")
      attribute :source, EventReference
    end
  end
end
