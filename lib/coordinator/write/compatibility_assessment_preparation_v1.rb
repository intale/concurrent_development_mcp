# frozen_string_literal: true

module Coordinator::Write
  class CompatibilityAssessmentPreparationV1 < Value
    attribute :evidence_id, Types::UuidV7
    attribute :submitted_at, Types::Timestamp
    attribute :input_digest, Types::Sha256Digest
    attribute :assessment_input_digest, Types::Sha256Digest
    attribute :evidence_event_id, Types::UuidV7
    attribute :terminal_event_id, Types::UuidV7
    attribute :completion_event_id, Types::UuidV7
    attribute :correlation_id, Types::UuidV7
  end
end
