# frozen_string_literal: true

module Coordinator::Write
  class CompatibilityAssessmentPreparationV1 < Value
    attribute :evidence_id, Types::UuidV7
    attribute :submitted_at, Types::Timestamp
    attribute :input_digest, Types::Sha256Digest
    attribute :assessment_input_digest, Types::Sha256Digest
    attribute :event_ids, Types::Array.of(Types::UuidV7).constrained(size: 3)
    attribute :correlation_id, Types::UuidV7
  end
end
