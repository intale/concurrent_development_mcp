# frozen_string_literal: true

module Coordinator::Read
  class InterpretationAdjudicationV1 < Value
    attribute :action, Types::InterpretationAdjudicationAction
    attribute :outcome, Types::InterpretationAdjudicationOutcome
    attribute :rationale, Coordinator::Write::Interpretations::AdjudicationRationaleV1.optional
    attribute :clarification, Coordinator::Write::Interpretations::AdjudicationClarificationV1.optional
    attribute :slot, Coordinator::Write::Interpretations::InterpretationSlotV1.optional
    attribute :actor, AttributedActorV1
    attribute :event, Coordinator::Write::EventReference
    attribute :adjudicated_at, Types::Timestamp
    attribute :causation_id, Types::UuidV7.optional
    attribute :correlation_id, Types::UuidV7.optional
  end
end
