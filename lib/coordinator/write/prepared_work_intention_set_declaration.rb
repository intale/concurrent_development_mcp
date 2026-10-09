# frozen_string_literal: true

module Coordinator::Write
  class PreparedWorkIntentionSetDeclaration < Value
    Resource = Types.Instance(PreparedWorkIntentionTargetV1)

    attribute :declared_at, Types::Timestamp
    attribute :expires_at, Types::Timestamp
    attribute :input_digest, Types::Sha256Digest
    attribute :intention_set_id, Types::UuidV7
    attribute :resources, Types::Array.of(Resource).constrained(min_size: 1, max_size: 32)
    attribute :set_event_id, Types::UuidV7
  end
end
