# frozen_string_literal: true

module Coordinator::Write
  module MergeSnapshotVerifications
    class VerificationDecisionReferenceV1 < Value
      attribute :verification_id, Types::UuidV7
      attribute :evidence_kind, Types::MergeSnapshotVerificationEvidenceKind
      attribute :conclusion, Types::String.enum("passed")
      attribute :result_digest, Types::Sha256Digest
      attribute :verification_input_digest, Types::Sha256Digest
      attribute :event, EventReference
    end
  end
end
