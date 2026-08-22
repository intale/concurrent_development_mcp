# frozen_string_literal: true

module Coordinator::Write
  class PreparedAcquisition < Value
    attribute :occurred_at, Types::Timestamp
    attribute :input_digest, Types::Sha256Digest
    attribute :domain_event_ids, Types::Array.of(Types::UuidV7).constrained(size: 3)
    attribute :completion_event_id, Types::UuidV7
  end
end
