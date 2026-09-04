# frozen_string_literal: true

module Coordinator::Write
  module Metadata
    class VerificationWaiverV2 < EventMetadata
      attribute :policy, CandidateObligations::ImpactPolicyEvidenceV1
      attribute :waiver_input_digest, Types::Sha256Digest
    end
  end
end
