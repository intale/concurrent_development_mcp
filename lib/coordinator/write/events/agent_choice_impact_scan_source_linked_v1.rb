# frozen_string_literal: true

module Coordinator::Write
  module Events
    class AgentChoiceImpactScanSourceLinkedV1 < Base
      contract type: "AgentChoiceImpactScanSourceLinked", version: 1

      attribute :scan_id, Types::UuidV7
      attribute :role, Types::String.enum("decision_change")
      attribute :source, EventReference
    end
  end
end
