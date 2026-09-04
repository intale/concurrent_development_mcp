# frozen_string_literal: true

module Coordinator::Write
  module MergeSnapshotVerifications
    class EvidenceObservationV1 < Value
      attribute :submission, Types.Instance(Events::MergeSnapshotVerificationSubmittedV2)
      attribute :event, EventReference
      attribute :policy_version, Types::MergeSnapshotVerificationPolicyVersion
      attribute :verification_input_digest, Types::Sha256Digest
    end
  end
end
