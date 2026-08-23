# frozen_string_literal: true

module Coordinator::Write
  module AgentChoiceImpacts
    class ChoiceSnapshotV1 < Value
      attribute :choice_id, Types::Identifier
      attribute :recorded, Events::AgentChoiceRecordedV1
      attribute :recorded_event, EventReference
      attribute :accepted, Events::AgentChoiceAcceptedV1
      attribute :accepted_event, EventReference
      attribute :invalidation, Events::AgentChoiceInvalidatedByDecisionV1.optional
      attribute :invalidation_event, EventReference.optional
    end
  end
end
