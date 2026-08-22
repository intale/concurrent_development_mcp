# frozen_string_literal: true

module Coordinator::Read
  class GuidanceUtteranceV1 < Value
    attribute :message_id, Types::Identifier
    attribute :conversation_id, Types::Identifier
    attribute :text, Types::GuidanceText
    attribute :source, Types::GuidanceSource
    attribute :anchors, Coordinator::Write::GuidanceAnchorsV1
    attribute :actor, AttributedActorV1
    attribute :policy_status, Types::EvidencePolicyStatus
    attribute :recorded_at, Types::Timestamp
    attribute :event, Coordinator::Write::EventReference
    attribute :causation_id, Types::UuidV7.optional
    attribute :correlation_id, Types::UuidV7.optional
  end
end
