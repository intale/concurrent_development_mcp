# frozen_string_literal: true

module Coordinator::Write
  class DevelopmentArtifactRelationPreparationV1 < Value
    attribute :declared_at, Types::Timestamp
    attribute :input_digest, Types::Sha256Digest
    attribute :domain_event_ids, Types::Array.of(Types::UuidV7).constrained(size: 2)
  end
end
