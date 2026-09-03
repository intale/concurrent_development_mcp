# frozen_string_literal: true

module Coordinator::Write
  class PreparedCandidateImpactSurfaceSubmission < Value
    attribute :derived_at, Types::Timestamp
    attribute :input_digest, Types::Sha256Digest
    attribute :surface_event_id, Types::UuidV7
    attribute :registration_event_id, Types::UuidV7
  end
end
