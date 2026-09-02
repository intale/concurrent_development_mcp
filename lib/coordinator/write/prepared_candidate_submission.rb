# frozen_string_literal: true

module Coordinator::Write
  class PreparedCandidateSubmission < Value
    attribute :submitted_at, Types::Timestamp
    attribute :input_digest, Types::Sha256Digest
    attribute :head_identity, Types.Instance(Candidates::HeadIdentityV1)
    attribute :candidate_event_id, Types::UuidV7
    attribute :manifest_event_id, Types::UuidV7
    attribute :build_context_event_id, Types::UuidV7.optional
    attribute :head_registration_event_id, Types::UuidV7
    attribute :attachment_event_id, Types::UuidV7
    attribute :completion_event_id, Types::UuidV7

    def with_head_identity(value)
      self.class.new(
        submitted_at:,
        input_digest:,
        head_identity: value,
        candidate_event_id:,
        manifest_event_id:,
        build_context_event_id:,
        head_registration_event_id:,
        attachment_event_id:,
        completion_event_id:
      )
    end
  end
end
