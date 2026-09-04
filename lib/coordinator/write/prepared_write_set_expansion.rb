# frozen_string_literal: true

module Coordinator::Write
  class PreparedWriteSetExpansion < Value
    Resource = Types.Instance(PreparedWorkIntentionTargetV1)

    attribute :expanded_at, Types::Timestamp
    attribute :input_digest, Types::Sha256Digest
    attribute :resources, Types::Array.of(Resource).constrained(min_size: 1, max_size: 32)
  end
end
