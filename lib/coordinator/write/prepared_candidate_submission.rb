# frozen_string_literal: true

module Coordinator::Write
  class PreparedCandidateSubmission < Value
    attribute :submitted_at, Types::Timestamp
    attribute :input_digest, Types::Sha256Digest
    attribute :head_identity, Types.Instance(Candidates::HeadIdentityV1)
    attribute :candidate_fact_event_ids, Types::Array.of(Types::UuidV7)
    attribute :head_registration_event_id, Types::UuidV7

    def with_head_identity(value)
      self.class.new(
        submitted_at:,
        input_digest:,
        head_identity: value,
        candidate_fact_event_ids:,
        head_registration_event_id:,
      )
    end
  end
end
