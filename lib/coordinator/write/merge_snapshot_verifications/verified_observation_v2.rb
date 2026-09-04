# frozen_string_literal: true

module Coordinator::Write
  module MergeSnapshotVerifications
    class VerifiedObservationV2 < Value
      attribute :selected, Events::MergeSnapshotVerificationSelectedV1
      attribute :selected_event, EventReference
      attribute :verified, Events::MergeSnapshotVerifiedV2
      attribute :verified_event, EventReference
      attribute :policy_version, Types::MergeSnapshotVerificationPolicyVersion
      attribute :verification_digest, Types::Sha256Digest
    end
  end
end
