# frozen_string_literal: true

module Coordinator::Write
  class InterpretationAdjudicationPreparationV1 < Value
    attribute :adjudicated_at, Types::Timestamp
    attribute :input_digest, Types::Sha256Digest
    attribute :lifecycle_event_id, Types::UuidV7
  end
end
