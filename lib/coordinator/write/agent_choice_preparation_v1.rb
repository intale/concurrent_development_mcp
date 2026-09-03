# frozen_string_literal: true

module Coordinator::Write
  class AgentChoicePreparationV1 < Value
    attribute :recorded_at, Types::Timestamp
    attribute :input_digest, Types::Sha256Digest
    attribute :recorded_event_id, Types::UuidV7
    attribute :accepted_event_id, Types::UuidV7
  end
end
