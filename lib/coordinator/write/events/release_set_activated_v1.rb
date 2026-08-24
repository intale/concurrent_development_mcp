# frozen_string_literal: true

module Coordinator::Write
  module Events
    class ReleaseSetActivatedV1 < Base
      contract type: "ReleaseSetActivated", version: 1

      attribute :release_set_id, Types::Identifier
      attribute :change_set_id, Types::Identifier
      attribute :release_digest, Types::Sha256Digest
      attribute :verification_event, EventReference
      attribute :verification_digest, Types::Sha256Digest
      attribute :activation_point, ReleaseSets::ActivationPointV1
      attribute :activation_digest, Types::Sha256Digest
      attribute :policy_version, Types::ReleaseSetActivationPolicyVersion
      attribute :evidence_status, Types::MergeSnapshotEvidenceStatus
      attribute :recorded_at, Types::Timestamp
    end
  end
end
