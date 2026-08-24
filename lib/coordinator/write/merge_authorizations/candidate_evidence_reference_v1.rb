# frozen_string_literal: true

module Coordinator::Write
  module MergeAuthorizations
    class CandidateEvidenceReferenceV1 < Value
      attribute :candidate_id, Types::Identifier
      attribute :candidate_event, EventReference
      attribute :manifest_event, EventReference
      attribute :surface_event, EventReference
      attribute :surface_registration_event, EventReference
      attribute :surface_digest, Types::Sha256Digest
    end
  end
end
