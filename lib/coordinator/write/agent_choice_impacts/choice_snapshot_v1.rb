# frozen_string_literal: true

module Coordinator::Write
  module AgentChoiceImpacts
    class ChoiceSnapshotV1 < Value
      attribute :choice_id, Types::Identifier
      attribute :recorded,
                Types.Instance(Events::AgentChoiceRecordedV1) |
                  Types.Instance(Events::AgentChoiceRecordedV2)
      attribute :recorded_event, EventReference
      attribute :accepted,
                Types.Instance(Events::AgentChoiceAcceptedV1) |
                  Types.Instance(Events::AgentChoiceAcceptedV2)
      attribute :accepted_event, EventReference
      attribute :invalidation,
                (
                  Types.Instance(Events::AgentChoiceInvalidatedByDecisionV1) |
                    Types.Instance(Events::AgentChoiceInvalidatedByDecisionV2)
                ).optional
      attribute :invalidation_event, EventReference.optional
    end
  end
end
