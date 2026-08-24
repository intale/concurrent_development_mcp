# frozen_string_literal: true

module Coordinator::Write
  module MergeAuthorizations
    class ObligationCheckV1 < Value
      attribute :obligation_id, Types::Identifier
      attribute :source_candidate_id, Types::Identifier
      attribute :target_candidate_id, Types::Identifier
      attribute :enforcement, Types::CandidateImpactPolicyEnforcementLevel
      attribute :required_evidence, Types::CandidateImpactRequiredEvidenceKinds
      attribute :identity_digest, Types::Sha256Digest
      attribute :status, Types::MergeAuthorizationObligationStatus
      attribute :validity_input_digest, Types::Sha256Digest.optional
      attribute :creation_event, EventReference.optional
      attribute :terminal_event, EventReference.optional
    end
  end
end
