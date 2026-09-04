# frozen_string_literal: true

module Coordinator::Processes
  module AgentChoiceImpacts
    class SourceV1 < Value
      Payload = Types.Instance(Coordinator::Write::Events::DecisionActivatedV1) |
                Types.Instance(Coordinator::Write::Events::DecisionActivatedV2) |
                Types.Instance(Coordinator::Write::Events::DecisionDefinitionCorrectedV1) |
                Types.Instance(Coordinator::Write::Events::DecisionDefinitionCorrectedV2) |
                Types.Instance(Coordinator::Write::Events::AgentChoiceAcceptedV1) |
                Types.Instance(Coordinator::Write::Events::AgentChoiceAcceptedV2) |
                Types.Instance(Coordinator::Write::Events::AgentChoiceImpactScanStartedV2) |
                Types.Instance(Coordinator::Write::Events::AgentChoiceImpactScanProgressedV2)

      attribute :event, Types.Instance(PgEventstore::Event)
      attribute :reference, Coordinator::Write::EventReference
      attribute :payload, Payload
    end
  end
end
